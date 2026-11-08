import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/auth/authenticate.dart';
import 'package:maktub_backend/features/auth/tokens.dart';
import 'package:maktub_backend/features/auth/who_am_i/who_am_i.dart';
import 'package:maktub_backend/features/auth/who_am_i/who_am_i_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _Context extends Mock implements RequestContext {}

class _FakeStore implements WhoAmIStore {
  final users = <String, Usuario>{};
  final memberships = <Membresia>[];
  final clubs = <Club>[];
  final athletes = <(String, String), String>{}; // (clubId, userId) -> athleteId

  @override
  Future<Usuario?> findUser(String userId) async => users[userId];

  @override
  Future<List<Membresia>> activeMemberships(String userId) async =>
      memberships.where((m) => m.usuarioId == userId && m.activa).toList();

  @override
  Future<List<Club>> clubsByIds(Set<String> clubIds) async => clubs.where((c) => clubIds.contains(c.id)).toList();

  @override
  Future<Map<String, String>> athleteIdsByClub(String userId, Set<String> clubIds) async => {
        for (final e in athletes.entries)
          if (e.key.$2 == userId && clubIds.contains(e.key.$1)) e.key.$1: e.value,
      };
}

void main() {
  final now = DateTime.utc(2026, 11, 7, 12);
  final audit = Auditoria.nueva('u1', ahora: now);

  Club club(String id, String name, TipoClub type) => Club(id: id, nombre: name, tipo: type, auditoria: audit);

  Membresia membership(String clubId, Set<Rol> roles, {EstadoMembresia state = EstadoMembresia.activa}) => Membresia(
        id: 'm-$clubId',
        clubId: clubId,
        usuarioId: 'u1',
        roles: roles,
        estado: state,
        desde: now,
        auditoria: audit,
      );

  late _FakeStore store;

  setUp(() {
    store = _FakeStore()
      ..users['u1'] = Usuario(
        id: 'u1',
        email: 'Ari@Example.com',
        nombre: 'Ari',
        emailVerificado: true,
        clubPersonalId: 'cp1',
        metodos: {MetodoIngreso.google},
      )
      ..clubs.addAll([club('cp1', 'Mi entrenamiento', TipoClub.personal), club('c1', 'Maktub', TipoClub.club), club('c2', 'Otro', TipoClub.club)]);
  });

  test('returns the user, the personal club and the active memberships with their roles', () async {
    store.memberships
      ..add(membership('cp1', {Rol.coach, Rol.atleta}))
      ..add(membership('c1', {Rol.atleta}));

    final json = (await WhoAmI(store)('u1')).toJson();

    expect((json['usuario']! as Map)['email'], 'ari@example.com');
    expect((json['clubPersonal']! as Map)['id'], 'cp1');
    final clubs = (json['clubes']! as List).cast<Map>();
    expect(clubs.map((c) => (c['club'] as Map)['id']), ['c1', 'cp1']);
    expect(clubs.first['roles'], ['atleta']);
    expect(clubs.last['roles'], ['coach', 'atleta']);
    expect(json['esAdminPlataforma'], isFalse);
  });

  test('each club carries the athlete id of the user in that club, or null', () async {
    store.memberships
      ..add(membership('cp1', {Rol.coach}))
      ..add(membership('c1', {Rol.coach, Rol.atleta}))
      ..add(membership('c2', {Rol.atleta}));
    store.athletes[('c1', 'u1')] = 'ath-c1';
    store.athletes[('c2', 'u2')] = 'ath-other-user';
    store.athletes[('c3', 'u1')] = 'ath-unrelated-club';

    final clubs = ((await WhoAmI(store)('u1')).toJson()['clubes']! as List).cast<Map>();
    final byClub = {for (final c in clubs) (c['club'] as Map)['id']: c['atletaId']};

    expect(byClub, {'c1': 'ath-c1', 'c2': null, 'cp1': null});
    expect(clubs.first.keys, containsAll(['club', 'roles', 'atletaId']));
  });

  test('an ended membership does not appear', () async {
    store.memberships
      ..add(membership('cp1', {Rol.coach}))
      ..add(membership('c1', {Rol.atleta}, state: EstadoMembresia.terminada));

    final clubs = ((await WhoAmI(store)('u1')).toJson()['clubes']! as List).cast<Map>();

    expect(clubs.map((c) => (c['club'] as Map)['id']), ['cp1']);
  });

  test('includes the platform admin flag', () async {
    store.users['u1'] = Usuario(
      id: 'u1',
      email: 'a@b.c',
      nombre: 'Ari',
      emailVerificado: true,
      clubPersonalId: 'cp1',
      esAdminPlataforma: true,
    );

    expect((await WhoAmI(store)('u1')).toJson()['esAdminPlataforma'], isTrue);
  });

  test('a token for a user that does not exist answers 401', () async {
    await expectLater(
      WhoAmI(store)('ghost'),
      throwsA(isA<ErrorDeSolicitud>().having((e) => e.estado, 'estado', HttpStatus.unauthorized)),
    );
  });

  group('behind requireUser', () {
    final codec = AccessTokenCodec('s' * 40);

    Future<Response> get(Map<String, String> headers, {DateTime? at}) async {
      final context = _Context();
      when(() => context.request).thenReturn(Request('GET', Uri.parse('http://localhost/me'), headers: headers));
      when(() => context.read<AccessTokenCodec>()).thenReturn(codec);
      when(() => context.provide<CurrentUser>(any())).thenAnswer((inv) {
        final user = (inv.positionalArguments.first as CurrentUser Function())();
        final inner = _Context();
        when(() => inner.read<CurrentUser>()).thenReturn(user);
        return inner;
      });
      Future<Response> handler(RequestContext c) async =>
          Response.json(body: (await WhoAmI(store)(c.read<CurrentUser>().userId)).toJson());
      return manejarErrores()(requireUser(now: () => at ?? now)(handler))(context);
    }

    test('no token or an expired token answers 401; a valid one answers 200', () async {
      final token = codec.issue(userId: 'u1', sessionId: 's1', now: now).token;

      expect((await get({})).statusCode, HttpStatus.unauthorized);
      expect((await get({'authorization': 'Bearer $token'}, at: now.add(accessTokenLifetime))).statusCode, HttpStatus.unauthorized);
      expect((await get({'authorization': 'Bearer $token'})).statusCode, HttpStatus.ok);
    });
  });
}
