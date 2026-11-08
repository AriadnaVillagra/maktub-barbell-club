import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/referencias/registrar_rm/registrar_rm.dart';
import 'package:maktub_backend/features/referencias/registrar_rm/registrar_rm_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

class _Context extends Mock implements RequestContext {}

/// Like Mongo, it only finds what belongs to the club it is asked about.
class _FakeStore implements RegisterRmStore {
  final athletes = <(String, String)>{}; // (clubId, athleteId)
  final exercises = <(String, String)>{}; // (clubId, exerciseId)
  final references = <Reference>[];
  final factors = <WorkFactor>[];

  @override
  Future<bool> athleteInClub(String clubId, String athleteId) async =>
      athletes.contains((clubId, athleteId));

  @override
  Future<bool> exerciseVisible(String clubId, String exerciseId) async =>
      exercises.contains((clubId, exerciseId)) ||
      exercises.contains((clubPlataforma, exerciseId));

  @override
  Future<void> insert(Reference reference) async => references.add(reference);
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
  final body = {'ejercicioId': 'squat', 'valor': 150, 'fecha': '2026-11-01'};

  _FakeStore seeded() => _FakeStore()
    ..athletes.add(('club-a', 'ath-1'))
    ..exercises.add((clubPlataforma, 'squat'));

  Future<Response> register(
    _FakeStore store,
    ClubContext ctx,
    Object? b, {
    String athleteId = 'ath-1',
  }) => _call(
    ctx,
    (c) => registerRmEndpoint(
      c,
      athleteId,
      store: store,
      newId: () => 'ref-1',
      now: () => now,
    ),
    b,
  );

  test(
    'the coach registers an RM: one new reference, server fields win',
    () async {
      final store = seeded();
      final r = await register(store, coach, {
        ...body,
        'clubId': 'club-b',
        'origen': 'importado',
        'id': 'forged',
      });
      expect(r.statusCode, HttpStatus.ok);
      final created = store.references.single;
      expect(created.id, 'ref-1');
      expect(created.clubId, 'club-a');
      expect(created.athleteId, 'ath-1');
      expect(created.exerciseId, 'squat');
      expect(created.type, ReferenceType.rm);
      expect(created.value, 150);
      expect(created.date, DateTime.utc(2026, 11, 1));
      expect(created.origin, ReferenceOrigin.testeado);
      expect(created.auditoria.creadoPor, 'coach-1');
      expect(created.auditoria.creadoEn, now);
      expect(
        Reference.fromJson(jsonDecode(await r.body()) as Json).id,
        'ref-1',
      );
    },
  );

  test('a new RM never modifies an earlier one', () async {
    final store = seeded();
    final earlier = Reference(
      id: 'old',
      clubId: 'club-a',
      athleteId: 'ath-1',
      exerciseId: 'squat',
      type: ReferenceType.rm,
      value: 140,
      date: DateTime.utc(2026, 2, 1),
      origin: ReferenceOrigin.testeado,
      auditoria: Auditoria.nueva('coach-1', ahora: DateTime.utc(2026, 2, 1)),
    );
    store.references.add(earlier);
    await register(store, coach, body);
    expect(store.references, hasLength(2));
    expect(store.references.first, same(earlier));
    expect(store.references.first.value, 140);
  });

  test(
    'after the RM, the factor in force reads 100 % and no factor is written',
    () async {
      final store = seeded();
      store.factors.add(
        WorkFactor(
          id: 'f1',
          clubId: 'club-a',
          athleteId: 'ath-1',
          exerciseId: 'squat',
          value: 80,
          date: DateTime.utc(2026, 10, 1),
          auditoria: Auditoria.nueva(
            'coach-1',
            ahora: DateTime.utc(2026, 10, 1),
          ),
        ),
      );
      double factorOn(DateTime on) => currentWorkFactor(
        store.factors,
        store.references,
        athleteId: 'ath-1',
        exerciseId: 'squat',
        on: on,
      );
      expect(factorOn(DateTime.utc(2026, 11, 8)), 80);
      await register(store, coach, body);
      expect(factorOn(DateTime.utc(2026, 11, 8)), 100);
      expect(
        factorOn(DateTime.utc(2026, 10, 15)),
        80,
        reason: 'a past RM date does not change earlier dates',
      );
      expect(store.factors, hasLength(1));
    },
  );

  test('an athlete is rejected with 403 and nothing is written', () async {
    final store = seeded();
    final r = await register(store, athlete, body);
    expect(r.statusCode, HttpStatus.forbidden);
    expect(jsonDecode(await r.body()), contains('error'));
    expect(store.references, isEmpty);
  });

  test('a coach of another club is rejected and nothing is written', () async {
    final store = seeded();
    final r = await register(store, otherCoach, body);
    expect(r.statusCode, HttpStatus.notFound);
    expect(jsonDecode(await r.body()), contains('error'));
    expect(store.references, isEmpty);
  });

  group('validation', () {
    for (final (name, b) in <(String, Map<String, Object?>)>[
      ('no exercise', {'valor': 150, 'fecha': '2026-11-01'}),
      ('zero value', {...body, 'valor': 0}),
      ('text value', {...body, 'valor': '150'}),
      ('no date', {'ejercicioId': 'squat', 'valor': 150}),
      ('bad date', {...body, 'fecha': '01/11/2026'}),
      ('unknown exercise', {...body, 'ejercicioId': 'nope'}),
      ('another type', {...body, 'tipo': 'marca'}),
    ]) {
      test('rejects $name with 400', () async {
        final store = seeded();
        final r = await register(store, coach, b);
        expect(r.statusCode, HttpStatus.badRequest);
        expect(store.references, isEmpty);
      });
    }

    test('an exercise of another club is not visible', () async {
      final store = seeded()..exercises.add(('club-b', 'private'));
      final r = await register(store, coach, {
        ...body,
        'ejercicioId': 'private',
      });
      expect(r.statusCode, HttpStatus.badRequest);
      expect(store.references, isEmpty);
    });
  });

  group('club isolation', () {
    final store = _FakeStore();
    final markers = <String, String>{};
    testClubIsolation(
      'POST /clubes/{clubId}/atletas/ath-1/referencias',
      endpoint: (c) => registerRmEndpoint(
        c,
        'ath-1',
        store: store,
        newId: () => markers[c.read<ClubContext>().clubId]!,
      ),
      path: '/clubes/{clubId}/atletas/ath-1/referencias',
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
