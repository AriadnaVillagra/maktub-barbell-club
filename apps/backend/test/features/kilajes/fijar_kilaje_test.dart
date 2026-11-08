import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/kilajes/fijar_kilaje/fijar_kilaje.dart';
import 'package:maktub_backend/features/kilajes/fijar_kilaje/fijar_kilaje_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

class _Context extends Mock implements RequestContext {}

/// Like Mongo, it only finds what belongs to the club it is asked about; one value per pair.
class _FakeStore implements SetFixedWeightStore {
  final athletes = <(String, String)>{};
  final exercises = <(String, String)>{};
  final weights = <FixedWeight>[];
  var writes = 0;

  @override
  Future<bool> athleteInClub(String clubId, String athleteId) async =>
      athletes.contains((clubId, athleteId));

  @override
  Future<bool> exerciseVisible(String clubId, String exerciseId) async =>
      exercises.contains((clubId, exerciseId)) ||
      exercises.contains((clubPlataforma, exerciseId));

  @override
  Future<FixedWeight?> find(
    String clubId,
    String athleteId,
    String exerciseId,
  ) async => weights
      .where(
        (w) =>
            w.clubId == clubId &&
            w.athleteId == athleteId &&
            w.exerciseId == exerciseId,
      )
      .firstOrNull;

  @override
  Future<void> save(FixedWeight weight) async {
    writes++;
    weights.removeWhere(
      (w) =>
          w.clubId == weight.clubId &&
          w.athleteId == weight.athleteId &&
          w.exerciseId == weight.exerciseId,
    );
    weights.add(weight);
  }
}

Future<Response> _call(ClubContext ctx, Handler endpoint, Object? body) async {
  final context = _Context();
  when(() => context.request).thenReturn(
    Request(
      'PUT',
      Uri.parse('http://localhost/x'),
      body: body is String ? body : jsonEncode(body),
    ),
  );
  when(() => context.read<ClubContext>()).thenReturn(ctx);
  return manejarErrores()(endpoint)(context);
}

void main() {
  var now = DateTime.utc(2026, 11, 8, 12);
  const coach = ClubContext(
    clubId: 'club-a',
    userId: 'coach-1',
    roles: {Rol.coach},
    clubType: TipoClub.club,
  );
  const coach2 = ClubContext(
    clubId: 'club-a',
    userId: 'coach-9',
    roles: {Rol.coach},
    clubType: TipoClub.club,
  );
  const otherCoach = ClubContext(
    clubId: 'club-b',
    userId: 'coach-2',
    roles: {Rol.coach},
    clubType: TipoClub.club,
  );
  const athlete = ClubContext(
    clubId: 'club-a',
    userId: 'ath-1',
    roles: {Rol.atleta},
    clubType: TipoClub.club,
  );
  final body = {'ejercicioId': 'db-press', 'kilos': 22.5};

  _FakeStore seeded() => _FakeStore()
    ..athletes.add(('club-a', 'ath-1'))
    ..exercises.add((clubPlataforma, 'db-press'));

  var counter = 0;
  Future<Response> set(
    _FakeStore store,
    ClubContext ctx,
    Object? b, {
    String athleteId = 'ath-1',
  }) => _call(
    ctx,
    (c) => setFixedWeightEndpoint(
      c,
      athleteId,
      store: store,
      newId: () => 'k-${++counter}',
      now: () => now,
    ),
    b,
  );

  test('the coach sets a fixed weight, server fields win', () async {
    final store = seeded();
    final r = await set(store, coach, {...body, 'clubId': 'club-b', 'id': 'x'});
    expect(r.statusCode, HttpStatus.ok);
    final created = store.weights.single;
    expect(created.clubId, 'club-a');
    expect(created.athleteId, 'ath-1');
    expect(created.exerciseId, 'db-press');
    expect(created.kg, 22.5);
    expect(created.id, isNot('x'));
    expect(created.auditoria.creadoPor, 'coach-1');
    expect(created.auditoria.modificadoPor, isNull);
    expect(FixedWeight.fromJson(jsonDecode(await r.body()) as Json).kg, 22.5);
  });

  test(
    'a second send replaces the value and stamps the modification',
    () async {
      final store = seeded();
      await set(store, coach, body);
      final firstId = store.weights.single.id;
      now = DateTime.utc(2026, 11, 20);
      await set(store, coach2, {...body, 'kilos': 25});
      final current = store.weights.single;
      expect(current.kg, 25);
      expect(current.id, firstId);
      expect(current.auditoria.creadoPor, 'coach-1');
      expect(current.auditoria.modificadoPor, 'coach-9');
      expect(current.auditoria.modificadoEn, now);
    },
  );

  test('another exercise gets its own weight', () async {
    final store = seeded()..exercises.add((clubPlataforma, 'curl'));
    await set(store, coach, body);
    await set(store, coach, {'ejercicioId': 'curl', 'kilos': 10});
    expect(store.weights, hasLength(2));
  });

  test('an athlete is rejected with 403 and nothing is written', () async {
    final store = seeded();
    final r = await set(store, athlete, body);
    expect(r.statusCode, HttpStatus.forbidden);
    expect(jsonDecode(await r.body()), contains('error'));
    expect(store.writes, 0);
  });

  test('a coach of another club is rejected and nothing is written', () async {
    final store = seeded();
    final r = await set(store, otherCoach, body);
    expect(r.statusCode, HttpStatus.notFound);
    expect(jsonDecode(await r.body()), contains('error'));
    expect(store.writes, 0);
  });

  group('validation', () {
    for (final (name, b) in <(String, Map<String, Object?>)>[
      ('no exercise', {'kilos': 20}),
      ('zero kilos', {...body, 'kilos': 0}),
      ('text kilos', {...body, 'kilos': '20'}),
      ('no kilos', {'ejercicioId': 'db-press'}),
      ('unknown exercise', {...body, 'ejercicioId': 'nope'}),
    ]) {
      test('rejects $name with 400', () async {
        final store = seeded();
        final r = await set(store, coach, b);
        expect(r.statusCode, HttpStatus.badRequest);
        expect(store.writes, 0);
      });
    }

    test('an unknown athlete is 404', () async {
      final store = seeded();
      final r = await set(store, coach, body, athleteId: 'nobody');
      expect(r.statusCode, HttpStatus.notFound);
      expect(store.writes, 0);
    });
  });

  group('club isolation', () {
    final store = _FakeStore();
    final markers = <String, String>{};
    testClubIsolation(
      'PUT /clubes/{clubId}/atletas/ath-1/kilajes',
      endpoint: (c) => setFixedWeightEndpoint(
        c,
        'ath-1',
        store: store,
        newId: () => markers[c.read<ClubContext>().clubId]!,
      ),
      path: '/clubes/{clubId}/atletas/ath-1/kilajes',
      action: Accion.editarReferencias,
      method: 'PUT',
      body: jsonEncode(body),
      seed: (clubId, marker) {
        markers[clubId] = marker;
        store.athletes.add((clubId, 'ath-1'));
        store.exercises.add((clubPlataforma, 'db-press'));
      },
    );
  });
}
