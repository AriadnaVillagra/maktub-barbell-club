import 'dart:io';

import 'package:maktub_backend/features/acceso/platform_context/platform_context_store.dart';
import 'package:maktub_backend/features/auth/google_login/google_login_store.dart';
import 'package:maktub_backend/features/club_requests/approve_club_request/approve_club_request_store.dart';
import 'package:maktub_backend/features/club_requests/list_club_requests/list_club_requests_store.dart';
import 'package:maktub_backend/features/club_requests/reject_club_request/reject_club_request_store.dart';
import 'package:maktub_backend/features/club_requests/request_club/request_club_store.dart';
import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:test/test.dart';

/// Needs a local MongoDB; uses a throwaway database and skips itself if none is reachable.
void main() {
  Db? db;
  final name = 'maktub_test_club_requests_${DateTime.now().microsecondsSinceEpoch}';

  setUpAll(() async {
    try {
      final base = Platform.environment['TEST_MONGO_URL'] ?? 'mongodb://localhost:27017';
      db = await abrirMongo('$base/$name');
      await asegurarIndices(db!);
    } on Object catch (e) {
      stderr.writeln('mongo: $e');
      db = null;
    }
  });

  tearDownAll(() async {
    await db?.drop();
    await db?.close();
  });

  void mongoTest(String description, Future<void> Function() body) {
    test(description, () async {
      if (db == null) {
        markTestSkipped('MongoDB no disponible');
        return;
      }
      await body();
    });
  }

  ClubRequest pending(String id, String email, DateTime at) => ClubRequest(
    id: id,
    email: email,
    requesterName: 'Lu',
    clubName: 'Barra $id',
    auditoria: Auditoria.nueva(email, ahora: at),
  );

  mongoTest('one pending request per email; the latest state is what sign-in sees', () async {
    final store = MongoRequestClubStore(db!);
    final login = MongoGoogleLoginStore(db!);
    final t = DateTime.utc(2026, 11, 21, 10);

    expect(await store.latestStatus('lu@example.com'), isNull);
    expect(await store.insertPending(pending('r1', 'lu@example.com', t), googleSub: 'sub-1'), isTrue);
    expect(await store.insertPending(pending('r2', 'lu@example.com', t.add(const Duration(hours: 1))), googleSub: 'sub-1'), isFalse);
    expect(await store.latestStatus('lu@example.com'), ClubRequestStatus.pending);
    expect(await login.latestClubRequestStatus('lu@example.com'), ClubRequestStatus.pending);

    final rejected = await MongoRejectClubRequestStore(db!).markRejected('r1', reviewedBy: 'u-andi', reviewedAt: t);
    expect(rejected!.status, ClubRequestStatus.rejected);
    expect(await login.latestClubRequestStatus('lu@example.com'), ClubRequestStatus.rejected);

    // A new one after the rejection is allowed and is now the latest.
    expect(await store.insertPending(pending('r3', 'lu@example.com', t.add(const Duration(hours: 2))), googleSub: 'sub-1'), isTrue);
    expect(await login.latestClubRequestStatus('lu@example.com'), ClubRequestStatus.pending);

    final doc = await db!.collection(Colecciones.clubRequests).findOne({'_id': 'r3'});
    expect((doc!['clubId'], doc['googleSub'], doc['estado']), (clubPlataforma, 'sub-1', 'pendiente'));

    final listed = await MongoListClubRequestsStore(db!).list(status: ClubRequestStatus.pending);
    expect([for (final r in listed) r.id], ['r3']);
    expect(await MongoListClubRequestsStore(db!).list(), hasLength(2));
  });

  mongoTest('approving marks the request once and inserts only what is missing', () async {
    final t = DateTime.utc(2026, 11, 21, 11);
    await MongoRequestClubStore(db!).insertPending(pending('a1', 'mo@example.com', t), googleSub: 'sub-mo');
    final store = MongoApproveClubRequestStore(db!);

    final first = await store.markApproved('a1', clubId: 'club-mo', reviewedBy: 'u-andi', reviewedAt: t);
    expect((first!.request.status, first.request.createdClubId, first.googleSub), (ClubRequestStatus.approved, 'club-mo', 'sub-mo'));
    final second = await store.markApproved('a1', clubId: 'other', reviewedBy: 'u-ari', reviewedAt: t);
    expect((second!.request.createdClubId, second.request.reviewedBy), ('club-mo', 'u-andi'));
    expect(await MongoRejectClubRequestStore(db!).markRejected('a1', reviewedBy: 'u-ari', reviewedAt: t).then((r) => r!.status), ClubRequestStatus.approved);

    final audit = Auditoria.nueva('u-andi', ahora: t);
    final user = await store.insertUserIfMissing(
      Usuario(id: 'u-mo', email: 'mo@example.com', nombre: 'Mo', emailVerificado: true, clubPersonalId: 'p-mo', metodos: const {MetodoIngreso.google}),
      googleSub: 'sub-mo',
      auditoria: audit,
    );
    final again = await store.insertUserIfMissing(
      Usuario(id: 'u-other', email: 'mo@example.com', nombre: 'Otro', emailVerificado: true, clubPersonalId: 'p-other'),
      auditoria: audit,
    );
    expect((user.id, again.id, again.clubPersonalId), ('u-mo', 'u-mo', 'p-mo'));
    final userDoc = await db!.collection(Colecciones.usuarios).findOne({'_id': 'u-mo'});
    expect(userDoc!['googleSub'], 'sub-mo');
    expect(userDoc['metodos'], ['google']);
    expect(await MongoGoogleLoginStore(db!).findByEmail('mo@example.com'), (id: 'u-mo', googleSub: 'sub-mo'));

    final club = Club(id: 'club-mo', nombre: 'Barra a1', tipo: TipoClub.club, auditoria: audit);
    final membership = Membresia(
      id: 'm1',
      clubId: 'club-mo',
      usuarioId: 'u-mo',
      roles: const {Rol.adminClub, Rol.coach, Rol.atleta},
      estado: EstadoMembresia.activa,
      desde: t,
      auditoria: audit,
    );
    final athlete = Atleta(id: 'at1', clubId: 'club-mo', usuarioId: 'u-mo', nombreVisible: 'Mo', auditoria: audit);
    for (var i = 0; i < 2; i++) {
      await store.ensureClub(club);
      await store.ensureMembership(i == 0 ? membership : membership.copiarCon(roles: const {Rol.atleta}));
      await store.ensureAthlete(athlete);
    }
    expect(await db!.collection(Colecciones.clubes).count({'_id': 'club-mo'}), 1);
    final memberships = await db!.collection(Colecciones.membresias).find({'clubId': 'club-mo'}).toList();
    expect(memberships, hasLength(1));
    expect(memberships.single['roles'], ['coach', 'atleta', 'admin_club']);
    expect(await db!.collection(Colecciones.atletas).count({'clubId': 'club-mo'}), 1);
  });

  mongoTest('the platform admin flag is read from the user', () async {
    await db!.collection(Colecciones.usuarios).insertMany([
      {'_id': 'u-admin', 'email': 'admin@example.com', 'esAdminPlataforma': true},
      {'_id': 'u-plain', 'email': 'plain@example.com'},
    ]);
    final store = MongoPlatformContextStore(db!);
    expect(await store.isPlatformAdmin('u-admin'), isTrue);
    expect(await store.isPlatformAdmin('u-plain'), isFalse);
    expect(await store.isPlatformAdmin('nobody'), isFalse);
  });
}
