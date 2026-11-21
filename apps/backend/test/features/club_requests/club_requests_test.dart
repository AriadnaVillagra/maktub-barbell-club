import 'dart:io';

import 'package:maktub_backend/features/acceso/platform_context/platform_context.dart';
import 'package:maktub_backend/features/auth/google_id_token.dart';
import 'package:maktub_backend/features/club_requests/approve_club_request/approve_club_request.dart';
import 'package:maktub_backend/features/club_requests/list_club_requests/list_club_requests.dart';
import 'package:maktub_backend/features/club_requests/reject_club_request/reject_club_request.dart';
import 'package:maktub_backend/features/club_requests/request_club/request_club.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

import 'fake_requests.dart';

/// Accepts tokens of the form `ok:<sub>:<email>`; anything else is rejected like a bad signature.
Future<GoogleIdentity> _verify(String token) async {
  final parts = token.split(':');
  if (parts.length == 3 && parts[0] == 'ok') return GoogleIdentity(sub: parts[1], email: parts[2]);
  throw const InvalidGoogleToken(GoogleTokenRejection.invalidSignature);
}

void main() {
  const admin = PlatformContext(userId: 'u-andi', isPlatformAdmin: true);
  late FakeClubRequests db;
  late DateTime now;
  late int n;
  late RequestClub request;
  late ApproveClubRequest approve;
  late RejectClubRequest reject;

  setUp(() {
    db = FakeClubRequests();
    now = DateTime.utc(2026, 11, 21, 10);
    n = 0;
    String newId() => 'id${n++}';
    request = RequestClub(db, _verify, now: () => now = now.add(const Duration(minutes: 1)), newId: newId);
    approve = ApproveClubRequest(db, now: () => now, newId: newId);
    reject = RejectClubRequest(db, now: () => now);
  });

  Map<String, dynamic> body({String token = 'ok:sub-1:Lu@Example.com', String club = ' Barra Norte ', String name = 'Lu', Object? note}) =>
      {'idToken': token, 'nombreClub': club, 'nombre': name, 'nota': ?note};

  Matcher rejectedWith(int status, {String? code}) => throwsA(
    isA<ErrorDeSolicitud>()
        .having((e) => e.estado, 'estado', status)
        .having((e) => e.extra['codigo'], 'codigo', code),
  );

  group('request', () {
    test('stores a pending request for the proven email, with its Google account and nothing else', () async {
      final r = await request(body(note: ' Somos 8 '));

      expect((r.email, r.clubName, r.requesterName, r.note, r.status), ('lu@example.com', 'Barra Norte', 'Lu', 'Somos 8', ClubRequestStatus.pending));
      expect(r.clubId, clubPlataforma);
      expect(db.googleSubs[r.id], 'sub-1');
      expect(db.users, isEmpty);
      expect(db.clubs, isEmpty);
      expect(db.memberships, isEmpty);
    });

    test('needs a valid Google ID token', () async {
      await expectLater(request(body(token: 'forged')), rejectedWith(HttpStatus.unauthorized));
      await expectLater(request({'nombreClub': 'Club', 'nombre': 'Lu'}), rejectedWith(HttpStatus.badRequest));
      expect(db.requests, isEmpty);
    });

    test('validates names and note', () async {
      await expectLater(request(body(club: 'B')), rejectedWith(HttpStatus.badRequest));
      await expectLater(request(body(name: '  ')), rejectedWith(HttpStatus.badRequest));
      await expectLater(request(body(club: 'x' * 61)), rejectedWith(HttpStatus.badRequest));
      await expectLater(request(body(note: 'x' * 501)), rejectedWith(HttpStatus.badRequest));
      await expectLater(request(body(note: 3)), rejectedWith(HttpStatus.badRequest));
      expect(db.requests, isEmpty);
    });

    test('one pending request per email', () async {
      await request(body());
      await expectLater(
        request(body(token: 'ok:sub-1:lu@example.com', club: 'Otro club')),
        rejectedWith(HttpStatus.conflict, code: 'pedido_pendiente'),
      );
      expect(db.requests, hasLength(1));
    });

    test('an email with an account cannot request', () async {
      db.users['lu@example.com'] = Usuario(id: 'u-lu', email: 'lu@example.com', nombre: 'Lu', emailVerificado: true, clubPersonalId: 'p');
      await expectLater(request(body()), rejectedWith(HttpStatus.conflict));
      expect(db.requests, isEmpty);
    });

    test('after a rejection a new request may be sent', () async {
      final first = await request(body());
      await reject(admin, first.id);
      final second = await request(body(club: 'Barra Sur'));

      expect(second.isPending, isTrue);
      expect(db.requests, hasLength(2));
      expect(await db.latestStatus('lu@example.com'), ClubRequestStatus.pending);
    });
  });

  group('list', () {
    test('the pending ones by default, oldest first; any state on request', () async {
      final a = await request(body(token: 'ok:s:a@example.com'));
      final b = await request(body(token: 'ok:s:b@example.com'));
      final c = await request(body(token: 'ok:s:c@example.com'));
      await reject(admin, b.id);

      expect([for (final r in await ListClubRequests(db)(null)) r.id], [a.id, c.id]);
      expect([for (final r in await ListClubRequests(db)('rechazado')) r.id], [b.id]);
      expect(await ListClubRequests(db)('todos'), hasLength(3));
      await expectLater(ListClubRequests(db)('cualquiera'), rejectedWith(HttpStatus.badRequest));
    });
  });

  group('approve', () {
    test('creates the club, the user with their personal club, memberships and athletes', () async {
      final r = await request(body());
      final approved = await approve(admin, r.id);

      final stored = db.requests[r.id]!;
      expect((stored.status, stored.reviewedBy, stored.createdClubId), (ClubRequestStatus.approved, 'u-andi', approved.club.id));

      final user = db.users['lu@example.com']!;
      expect((user.nombre, user.emailVerificado, user.esAdminPlataforma), ('Lu', true, false));
      expect(user.metodos, {MetodoIngreso.google});
      expect(db.userSubs['lu@example.com'], 'sub-1');
      expect(approved.userId, user.id);

      final club = db.clubs[approved.club.id]!;
      expect((club.nombre, club.tipo, club.auditoria.creadoPor), ('Barra Norte', TipoClub.club, user.id));
      expect(db.clubs[user.clubPersonalId]!.tipo, TipoClub.personal);

      Set<Rol> rolesIn(String clubId) => db.memberships.singleWhere((m) => m.clubId == clubId && m.usuarioId == user.id).roles;
      expect(rolesIn(club.id), {Rol.adminClub, Rol.coach, Rol.atleta});
      expect(rolesIn(user.clubPersonalId), {Rol.coach, Rol.atleta});
      expect({for (final a in db.athletes) a.clubId}, {club.id, user.clubPersonalId});
      expect(db.athletes.every((a) => a.usuarioId == user.id && a.nombreVisible == 'Lu'), isTrue);
    });

    test('approving again creates nothing new and completes a partial approval', () async {
      final r = await request(body());
      final first = await approve(admin, r.id);
      final counts = (db.users.length, db.clubs.length, db.memberships.length, db.athletes.length);

      final again = await approve(admin, r.id);
      expect(again.club.id, first.club.id);
      expect((db.users.length, db.clubs.length, db.memberships.length, db.athletes.length), counts);

      // A failure after the request was marked approved left the club without its membership and athlete.
      db.memberships.removeWhere((m) => m.clubId == first.club.id);
      db.athletes.removeWhere((a) => a.clubId == first.club.id);
      await approve(admin, r.id);
      expect((db.users.length, db.clubs.length, db.memberships.length, db.athletes.length), counts);
    });

    test('reuses a user who got an account meanwhile', () async {
      final r = await request(body());
      final existing = Usuario(id: 'u-lu', email: 'lu@example.com', nombre: 'Lucía', emailVerificado: true, clubPersonalId: 'p-lu');
      db.users['lu@example.com'] = existing;
      db.clubs['p-lu'] = Club(id: 'p-lu', nombre: 'Lucía', tipo: TipoClub.personal, auditoria: Auditoria.nueva('x', ahora: now));

      final approved = await approve(admin, r.id);
      expect(approved.userId, 'u-lu');
      expect(db.users, hasLength(1));
      expect(db.clubs['p-lu']!.nombre, 'Lucía');
      expect(db.memberships.singleWhere((m) => m.clubId == approved.club.id).usuarioId, 'u-lu');
    });

    test('an unknown request is 404 and a rejected one 409, with nothing created', () async {
      await expectLater(approve(admin, 'nope'), rejectedWith(HttpStatus.notFound));
      final r = await request(body());
      await reject(admin, r.id);
      await expectLater(approve(admin, r.id), rejectedWith(HttpStatus.conflict));
      expect(db.users, isEmpty);
      expect(db.clubs, isEmpty);
    });
  });

  group('reject', () {
    test('marks it rejected by the admin and creates nothing; again changes nothing', () async {
      final r = await request(body());
      final rejected = await reject(admin, r.id);
      expect((rejected.status, rejected.reviewedBy, rejected.reviewedAt), (ClubRequestStatus.rejected, 'u-andi', now));

      final again = await reject(admin, r.id);
      expect(again.status, ClubRequestStatus.rejected);
      expect(db.users, isEmpty);
      expect(db.clubs, isEmpty);
    });

    test('an approved request cannot be rejected; an unknown one is 404', () async {
      final r = await request(body());
      await approve(admin, r.id);
      await expectLater(reject(admin, r.id), rejectedWith(HttpStatus.conflict));
      await expectLater(reject(admin, 'nope'), rejectedWith(HttpStatus.notFound));
    });
  });

  group('platform context', () {
    test('only a platform admin can review club requests', () {
      const user = PlatformContext(userId: 'u1', isPlatformAdmin: false);
      expect(() => user.authorize(Accion.reviewClubRequests), throwsA(same(notAPlatformAdmin)));
      expect(admin.authorize(Accion.reviewClubRequests), same(admin));
      // The flag grants no club action through this context either.
      expect(admin.can(Accion.planificar), isFalse);
      expect(admin.can(Accion.gestionarMiembros), isFalse);
    });
  });
}
