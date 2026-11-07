import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context_store.dart';
import 'package:maktub_backend/features/auth/authenticate.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _Context extends Mock implements RequestContext {}

/// Behaves like the Mongo store: only `activa` memberships, filtered by club and user.
class _FakeStore implements ClubContextStore {
  final memberships = <Membresia>[];
  final clubs = <String, TipoClub>{};

  @override
  Future<Membresia?> activeMembership({required String clubId, required String userId}) async {
    for (final m in memberships) {
      if (m.clubId == clubId && m.usuarioId == userId && m.activa) return m;
    }
    return null;
  }

  @override
  Future<TipoClub?> clubType(String clubId) async => clubs[clubId];
}

void main() {
  final now = DateTime.utc(2026, 11, 7, 12);
  final audit = Auditoria.nueva('u1', ahora: now);

  Membresia membership(String clubId, Set<Rol> roles, {String userId = 'u1', EstadoMembresia state = EstadoMembresia.activa}) =>
      Membresia(
        id: 'm-$clubId-$userId',
        clubId: clubId,
        usuarioId: userId,
        roles: roles,
        estado: state,
        desde: now,
        auditoria: audit,
      );

  late _FakeStore store;

  setUp(() {
    store = _FakeStore()
      ..clubs.addAll({'c1': TipoClub.club, 'c2': TipoClub.club, 'cp1': TipoClub.personal});
  });

  /// Runs `requireClub` (and [action], if given) for `u1` on [path]; the handler echoes the context.
  Future<Response> call(String path, {Accion? action, String userId = 'u1'}) async {
    final context = _Context();
    when(() => context.request).thenReturn(Request('GET', Uri.parse('http://localhost$path')));
    when(() => context.read<CurrentUser>()).thenReturn(CurrentUser(userId: userId, sessionId: 's1'));
    when(() => context.provide<ClubContext>(any())).thenAnswer((inv) {
      final club = (inv.positionalArguments.first as ClubContext Function())();
      final inner = _Context();
      when(() => inner.read<ClubContext>()).thenReturn(club);
      return inner;
    });
    Response handler(RequestContext c) {
      final club = c.read<ClubContext>();
      return Response.json(body: {'clubId': club.clubId, 'userId': club.userId, 'roles': rolesACable(club.roles)});
    }

    final inner = action == null ? handler : requireAction(action)(handler);
    return manejarErrores()(requireClub(store: (_) => store)(inner))(context);
  }

  Future<Map<String, dynamic>> body(Response r) async => (jsonDecode(await r.body()) as Map).cast<String, dynamic>();

  group('requireClub', () {
    test('without a membership in that club, the request is rejected', () async {
      store.memberships.add(membership('c2', {Rol.coach}));

      final r = await call('/clubes/c1/planes');

      expect(r.statusCode, HttpStatus.forbidden);
      expect((await body(r))['error'], isNotEmpty);
    });

    test("another user's membership in the club does not count", () async {
      store.memberships.add(membership('c1', {Rol.coach}, userId: 'u2'));

      expect((await call('/clubes/c1/planes')).statusCode, HttpStatus.forbidden);
    });

    test('an ended membership gives no access', () async {
      store.memberships.add(membership('c1', {Rol.coach, Rol.atleta}, state: EstadoMembresia.terminada));

      expect((await call('/clubes/c1/planes')).statusCode, HttpStatus.forbidden);
    });

    test('with an active membership, the slice receives the clubId and the roles', () async {
      store.memberships
        ..add(membership('c1', {Rol.atleta}))
        ..add(membership('c2', {Rol.coach}));

      final r = await call('/clubes/c1/planes/p1');

      expect(r.statusCode, HttpStatus.ok);
      expect(await body(r), {'clubId': 'c1', 'userId': 'u1', 'roles': ['atleta']});
    });

    test('a path without a club is not found', () async {
      expect((await call('/clubes')).statusCode, HttpStatus.notFound);
    });
  });

  group('role for the action', () {
    test('an active membership without the role the action needs is rejected', () async {
      store.memberships.add(membership('c1', {Rol.atleta}));

      final r = await call('/clubes/c1/planes', action: Accion.planificar);

      expect(r.statusCode, HttpStatus.forbidden);
      expect((await body(r))['error'], forbiddenRole.mensaje);
    });

    test('an active membership with the role reaches the slice with clubId and roles', () async {
      store.memberships.add(membership('c1', {Rol.coach}));

      final r = await call('/clubes/c1/planes', action: Accion.planificar);

      expect(r.statusCode, HttpStatus.ok);
      expect(await body(r), {'clubId': 'c1', 'userId': 'u1', 'roles': ['coach']});
    });

    test('in the personal club the trimmed capabilities apply, whatever the roles', () async {
      store.memberships.add(membership('cp1', {Rol.coach, Rol.atleta}));

      expect((await call('/clubes/cp1/x', action: Accion.planificar)).statusCode, HttpStatus.forbidden);
      expect((await call('/clubes/cp1/x', action: Accion.seguirPlanPorDefecto)).statusCode, HttpStatus.ok);
    });

    test('authorize lets slices check a per-method action', () {
      const club = ClubContext(clubId: 'c1', userId: 'u1', roles: {Rol.atleta}, clubType: TipoClub.club);

      expect(club.authorize(Accion.registrar), same(club));
      expect(() => club.authorize(Accion.gestionarMiembros), throwsA(same(forbiddenRole)));
    });
  });

  test('clubIdFromPath reads the segment after clubes', () {
    expect(clubIdFromPath(Uri.parse('http://x/clubes/abc/planes')), 'abc');
    expect(clubIdFromPath(Uri.parse('http://x/clubes/abc')), 'abc');
    expect(clubIdFromPath(Uri.parse('http://x/clubes/')), isNull);
    expect(clubIdFromPath(Uri.parse('http://x/me')), isNull);
  });
}
