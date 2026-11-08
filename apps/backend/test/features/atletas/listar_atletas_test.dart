import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/atletas/listar_atletas/listar_atletas.dart';
import 'package:maktub_backend/features/atletas/listar_atletas/listar_atletas_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

class _Context extends Mock implements RequestContext {}

/// Like Mongo, it only returns the athletes of the club it is asked about.
class _FakeStore implements AthleteListStore {
  final all = <Atleta>[];

  @override
  Future<List<Atleta>> athletes(String clubId) async => [
    for (final a in all)
      if (a.clubId == clubId) a,
  ];
}

Atleta _athlete(String id, String clubId, String name, {String? userId}) =>
    Atleta(
      id: id,
      clubId: clubId,
      usuarioId: userId ?? 'user-$id',
      nombreVisible: name,
      auditoria: Auditoria.nueva('coach-1', ahora: DateTime.utc(2026, 11, 1)),
    );

Future<Response> _call(ClubContext ctx, _FakeStore store) async {
  final context = _Context();
  when(() => context.request)
      .thenReturn(Request('GET', Uri.parse('http://localhost/x')));
  when(() => context.read<ClubContext>()).thenReturn(ctx);
  return manejarErrores()((c) => listAthletesEndpoint(c, store: store))(
    context,
  );
}

void main() {
  const coach = ClubContext(
    clubId: 'club-a',
    userId: 'coach-1',
    roles: {Rol.coach},
    clubType: TipoClub.club,
  );
  const athleteOnly = ClubContext(
    clubId: 'club-a',
    userId: 'user-1',
    roles: {Rol.atleta},
    clubType: TipoClub.club,
  );
  const coachAthlete = ClubContext(
    clubId: 'club-a',
    userId: 'coach-1',
    roles: {Rol.coach, Rol.atleta},
    clubType: TipoClub.club,
  );
  const otherClubCoach = ClubContext(
    clubId: 'club-b',
    userId: 'coach-2',
    roles: {Rol.coach},
    clubType: TipoClub.club,
  );

  _FakeStore seeded() => _FakeStore()
    ..all.addAll([
      _athlete('a3', 'club-a', 'Carla'),
      _athlete('a1', 'club-a', 'Ana'),
      _athlete('a2', 'club-a', 'beto'),
      _athlete('b1', 'club-b', 'Zoe'),
    ]);

  test(
    'a coach lists the athletes of the club with only the three agreed fields',
    () async {
      final r = await _call(coach, seeded());

      expect(r.statusCode, HttpStatus.ok);
      final body = jsonDecode(await r.body()) as List;
      expect(body.first, {
        'id': 'a1',
        'usuarioId': 'user-a1',
        'nombreVisible': 'Ana',
      });
      expect(body, everyElement(hasLength(3)));
    },
  );

  test(
    'the list is sorted alphabetically by nombreVisible, ignoring case',
    () async {
      final r = await _call(coach, seeded());

      final names = [
        for (final a in jsonDecode(await r.body()) as List)
          (a as Map)['nombreVisible'],
      ];
      expect(names, ['Ana', 'beto', 'Carla']);
    },
  );

  test('equal names are ordered by id, so the order is stable', () async {
    final store = _FakeStore()
      ..all.addAll([
        _athlete('a2', 'club-a', 'Ana'),
        _athlete('a1', 'club-a', 'Ana'),
      ]);

    final r = await _call(coach, store);

    expect(
      [for (final a in jsonDecode(await r.body()) as List) (a as Map)['id']],
      ['a1', 'a2'],
    );
  });

  test('a coach that is also an athlete appears in the list', () async {
    final store = seeded()
      ..all.add(_athlete('a9', 'club-a', 'Andi', userId: 'coach-1'));

    final r = await _call(coachAthlete, store);

    final users = [
      for (final a in jsonDecode(await r.body()) as List)
        (a as Map)['usuarioId'],
    ];
    expect(users, contains('coach-1'));
  });

  test('an athlete gets 403', () async {
    final r = await _call(athleteOnly, seeded());

    expect(r.statusCode, HttpStatus.forbidden);
    expect(await r.body(), isNot(contains('Ana')));
  });

  test('a coach of another club sees only that club', () async {
    final r = await _call(otherClubCoach, seeded());

    final body = await r.body();
    expect(body, contains('Zoe'));
    expect(body, isNot(contains('Ana')));
  });

  test('a club without athletes answers an empty list', () async {
    final r = await _call(coach, _FakeStore());

    expect(r.statusCode, HttpStatus.ok);
    expect(jsonDecode(await r.body()), isEmpty);
  });

  group('club isolation', () {
    final store = _FakeStore();
    testClubIsolation(
      'GET /clubes/{clubId}/atletas',
      endpoint: (c) => listAthletesEndpoint(c, store: store),
      path: '/clubes/{clubId}/atletas',
      action: Accion.verReportesDeTodos,
      seed: (clubId, marker) =>
          store.all.add(_athlete('id-$marker', clubId, marker)),
    );
  });
}
