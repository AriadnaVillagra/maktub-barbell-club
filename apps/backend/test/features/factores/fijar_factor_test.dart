import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/factores/fijar_factor/fijar_factor.dart';
import 'package:maktub_backend/features/factores/fijar_factor/fijar_factor_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

class _Context extends Mock implements RequestContext {}

/// Like Mongo, it only finds what belongs to the club it is asked about.
class _FakeStore implements SetFactorStore {
  final athletes = <(String, String)>{};
  final exercises = <(String, String)>{};
  final factors = <WorkFactor>[];

  @override
  Future<bool> athleteInClub(String clubId, String athleteId) async =>
      athletes.contains((clubId, athleteId));

  @override
  Future<bool> exerciseVisible(String clubId, String exerciseId) async =>
      exercises.contains((clubId, exerciseId)) ||
      exercises.contains((clubPlataforma, exerciseId));

  @override
  Future<void> insert(WorkFactor factor) async => factors.add(factor);
}

Future<Response> _call(ClubContext ctx, Handler endpoint, Object? body) async {
  final context = _Context();
  when(() => context.request).thenReturn(
    Request(
      'POST',
      Uri.parse('http://localhost/x'),
      body: body is String ? body : jsonEncode(body),
    ),
  );
  when(() => context.read<ClubContext>()).thenReturn(ctx);
  return manejarErrores()(endpoint)(context);
}

void main() {
  final now = DateTime.utc(2026, 11, 8, 12);
  const coach = ClubContext(
    clubId: 'club-a',
    userId: 'coach-1',
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
  final body = {'ejercicioId': 'squat', 'valor': 80, 'fecha': '2026-11-01'};

  _FakeStore seeded() => _FakeStore()
    ..athletes.add(('club-a', 'ath-1'))
    ..exercises.add((clubPlataforma, 'squat'));

  var counter = 0;
  Future<Response> set(
    _FakeStore store,
    ClubContext ctx,
    Object? b, {
    String athleteId = 'ath-1',
  }) => _call(
    ctx,
    (c) => setFactorEndpoint(
      c,
      athleteId,
      store: store,
      newId: () => 'f-${++counter}',
      now: () => now,
    ),
    b,
  );

  test('the coach sets a factor: one new entry, server fields win', () async {
    final store = seeded();
    final r = await set(store, coach, {
      ...body,
      'clubId': 'club-b',
      'id': 'forged',
    });
    expect(r.statusCode, HttpStatus.ok);
    final created = store.factors.single;
    expect(created.clubId, 'club-a');
    expect(created.athleteId, 'ath-1');
    expect(created.exerciseId, 'squat');
    expect(created.value, 80);
    expect(created.date, DateTime.utc(2026, 11, 1));
    expect(created.id, isNot('forged'));
    expect(created.auditoria.creadoPor, 'coach-1');
    expect(created.auditoria.creadoEn, now);
    expect(WorkFactor.fromJson(jsonDecode(await r.body()) as Json).value, 80);
  });

  test('a second factor keeps the earlier entries of the history', () async {
    final store = seeded();
    await set(store, coach, body);
    final first = store.factors.single;
    await set(store, coach, {...body, 'valor': 90, 'fecha': '2026-12-01'});
    expect(store.factors, hasLength(2));
    expect(store.factors.first, same(first));
    expect(store.factors.first.value, 80);
    expect(store.factors.last.value, 90);
    expect(store.factors.first.id, isNot(store.factors.last.id));
    expect(
      currentWorkFactor(
        store.factors,
        const [],
        athleteId: 'ath-1',
        exerciseId: 'squat',
        on: DateTime.utc(2026, 11, 15),
      ),
      80,
    );
  });

  test('an athlete is rejected with 403 and nothing is written', () async {
    final store = seeded();
    final r = await set(store, athlete, body);
    expect(r.statusCode, HttpStatus.forbidden);
    expect(jsonDecode(await r.body()), contains('error'));
    expect(store.factors, isEmpty);
  });

  test('a coach of another club is rejected and nothing is written', () async {
    final store = seeded();
    final r = await set(store, otherCoach, body);
    expect(r.statusCode, HttpStatus.notFound);
    expect(jsonDecode(await r.body()), contains('error'));
    expect(store.factors, isEmpty);
  });

  group('validation', () {
    for (final (name, b) in <(String, Map<String, Object?>)>[
      ('no exercise', {'valor': 80, 'fecha': '2026-11-01'}),
      ('zero value', {...body, 'valor': 0}),
      ('text value', {...body, 'valor': '80'}),
      ('no date', {'ejercicioId': 'squat', 'valor': 80}),
      ('bad date', {...body, 'fecha': '01/11/2026'}),
      ('unknown exercise', {...body, 'ejercicioId': 'nope'}),
    ]) {
      test('rejects $name with 400', () async {
        final store = seeded();
        final r = await set(store, coach, b);
        expect(r.statusCode, HttpStatus.badRequest);
        expect(store.factors, isEmpty);
      });
    }

    test('an unknown athlete is 404', () async {
      final store = seeded();
      final r = await set(store, coach, body, athleteId: 'nobody');
      expect(r.statusCode, HttpStatus.notFound);
      expect(store.factors, isEmpty);
    });
  });

  group('club isolation', () {
    final store = _FakeStore();
    final markers = <String, String>{};
    testClubIsolation(
      'POST /clubes/{clubId}/atletas/ath-1/factores',
      endpoint: (c) => setFactorEndpoint(
        c,
        'ath-1',
        store: store,
        newId: () => markers[c.read<ClubContext>().clubId]!,
      ),
      path: '/clubes/{clubId}/atletas/ath-1/factores',
      action: Accion.editarReferencias,
      method: 'POST',
      body: jsonEncode(body),
      seed: (clubId, marker) {
        markers[clubId] = marker;
        store.athletes.add((clubId, 'ath-1'));
        store.exercises.add((clubPlataforma, 'squat'));
      },
    );
  });
}
