import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/plan/guardar/guardar.dart';
import 'package:maktub_backend/features/plan/guardar/guardar_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

class _Context extends Mock implements RequestContext {}

class _FakeStore implements SavePlanStore {
  final plans = <Plan>[];
  final catalog = <String, Exercise>{};

  /// Simulates a write that fails midway: nothing may change.
  bool failOnReplace = false;

  @override
  Future<Plan?> plan(String clubId, String planId) async {
    for (final p in plans) {
      if (p.clubId == clubId && p.id == planId) return p;
    }
    return null;
  }

  @override
  Future<Map<String, Exercise>> exercises(String clubId) async => catalog;

  @override
  Future<bool> replace(Plan plan) async {
    if (failOnReplace) throw StateError('write failed');
    final i = plans.indexWhere(
      (p) => p.clubId == plan.clubId && p.id == plan.id,
    );
    if (i < 0) return false;
    plans[i] = plan;
    return true;
  }
}

final _t0 = DateTime.utc(2026, 11, 1, 10);
final _t1 = DateTime.utc(2026, 11, 6, 9);

Exercise _exercise(String id, {List<String> categories = const ['cat-1']}) =>
    Exercise(
      id: id,
      clubId: 'plataforma',
      name: id,
      categoryIds: categories,
      metrics: const [Metric.reps, Metric.loadPctRm],
      auditoria: Auditoria.nueva('sys', ahora: _t0),
    );

Plan _stored(String clubId, {String id = 'p1', String createdBy = 'coach-1'}) =>
    Plan(
      id: id,
      clubId: clubId,
      name: 'Old',
      auditoria: Auditoria.nueva(createdBy, ahora: _t0),
    );

Json _validBody({int pct = 80}) => {
  'nombre': 'Octubre',
  'tipo': 'regular',
  'modelosSemana': [
    {
      'id': 'A',
      'nombre': 'A',
      'dias': [
        {
          'nombre': 'Lunes',
          'bloques': [
            {
              'nombre': 'Fuerza',
              'categoriaId': 'cat-1',
              'prescripciones': [
                {
                  'ejercicioId': 'ex-1',
                  'series': [
                    {'reps': 5, 'pct': pct},
                  ],
                },
              ],
            },
          ],
        },
      ],
    },
  ],
  'asignacion': ['A', 'A', 'A', 'A'],
};

ClubContext _ctx(String clubId, Set<Rol> roles, {String userId = 'coach-2'}) =>
    ClubContext(
      clubId: clubId,
      userId: userId,
      roles: roles,
      clubType: TipoClub.club,
    );

Future<Response> _save(
  ClubContext ctx,
  _FakeStore store,
  Object? body, {
  String planId = 'p1',
}) async {
  final context = _Context();
  when(() => context.request).thenReturn(
    Request('PUT', Uri.parse('http://localhost/x'), body: jsonEncode(body)),
  );
  when(() => context.read<ClubContext>()).thenReturn(ctx);
  return manejarErrores()(
    (c) => savePlanEndpoint(c, planId, store: store, now: () => _t1),
  )(context);
}

Future<Map<String, dynamic>> _json(Response r) async =>
    jsonDecode(await r.body()) as Map<String, dynamic>;

void main() {
  final coachA = _ctx('club-a', {Rol.coach});

  _FakeStore storeWithPlan() => _FakeStore()
    ..plans.add(_stored('club-a'))
    ..catalog['ex-1'] = _exercise('ex-1');

  test(
    'replaces the whole plan and records who modified it and when',
    () async {
      final store = storeWithPlan();
      final r = await _save(coachA, store, _validBody());

      expect(r.statusCode, HttpStatus.ok);
      final saved = store.plans.single;
      expect(saved.name, 'Octubre');
      expect(saved.weekModels.single.days.single.blocks.single.name, 'Fuerza');
      expect(await _json(r), saved.toJson());
      expect(saved.auditoria.creadoPor, 'coach-1');
      expect(saved.auditoria.creadoEn, _t0);
      expect(saved.auditoria.modificadoPor, 'coach-2');
      expect(saved.auditoria.modificadoEn, _t1);
    },
  );

  test('updates in place: no duplicate is created', () async {
    final store = storeWithPlan();
    await _save(coachA, store, _validBody());
    await _save(coachA, store, _validBody(pct: 85));

    expect(store.plans, hasLength(1));
  });

  test('saving the same payload twice gives the same plan', () async {
    final store = storeWithPlan();
    await _save(coachA, store, _validBody());
    final first = store.plans.single.toJson();
    await _save(coachA, store, _validBody());

    expect(store.plans.single.toJson(), first);
  });

  test('an id, clubId or audit forged in the body is ignored', () async {
    final store = storeWithPlan()..plans.add(_stored('club-b', id: 'p1'));
    await _save(coachA, store, {
      ..._validBody(),
      'id': 'other',
      'clubId': 'club-b',
      'auditoria': {'creadoPor': 'evil', 'creadoEn': '2000-01-01T00:00:00Z'},
    });

    final saved = store.plans.firstWhere((p) => p.clubId == 'club-a');
    expect(saved.id, 'p1');
    expect(saved.auditoria.creadoPor, 'coach-1');
    expect(store.plans.where((p) => p.id == 'other'), isEmpty);
    expect(store.plans.firstWhere((p) => p.clubId == 'club-b').name, 'Old');
  });

  test('an invalid plan is 422 with every problem and its location, and nothing is written', () async {
    final store = storeWithPlan();
    final body = _validBody(pct: 0)
      ..['nombre'] = '  '
      ..['asignacion'] = ['A', 'Z', 'A', 'A'];
    final r = await _save(coachA, store, body);

    expect(r.statusCode, HttpStatus.unprocessableEntity);
    final json = await _json(r);
    expect(json['error'], isA<String>());
    expect(json['problemas'], [
      {'codigo': 'nameEmpty'},
      {
        'codigo': 'setWithoutPct',
        'modeloSemana': 0,
        'dia': 0,
        'bloque': 0,
        'prescripcion': 0,
        'serie': 0,
      },
      {'codigo': 'assignmentUnknownModel', 'semana': 1},
    ]);
    expect(store.plans.single.name, 'Old');
  });

  test('an exercise unknown to the club is a problem', () async {
    final store = storeWithPlan()..catalog.clear();
    final r = await _save(coachA, store, _validBody());

    expect(r.statusCode, HttpStatus.unprocessableEntity);
    expect(
      (await _json(r))['problemas'],
      contains(containsPair('codigo', 'prescriptionUnknownExercise')),
    );
  });

  test('a write that fails midway leaves the previous plan intact', () async {
    final store = storeWithPlan()..failOnReplace = true;
    final r = await _save(coachA, store, _validBody());

    expect(r.statusCode, HttpStatus.internalServerError);
    expect(store.plans.single.name, 'Old');
    expect(store.plans.single.weekModels, isEmpty);
  });

  test('an unknown plan is 404', () async {
    final r = await _save(coachA, storeWithPlan(), _validBody(), planId: 'zz');

    expect(r.statusCode, HttpStatus.notFound);
  });

  test('a plan of another club is 404 and is not changed', () async {
    final store = storeWithPlan();
    final r = await _save(_ctx('club-b', {Rol.coach}), store, _validBody());

    expect(r.statusCode, HttpStatus.notFound);
    expect(store.plans.single.name, 'Old');
  });

  test('malformed JSON shapes are 400', () async {
    final store = storeWithPlan();
    for (final body in [
      {..._validBody(), 'modelosSemana': 'x'},
      {..._validBody(), 'tipo': 'otro'},
    ]) {
      final r = await _save(coachA, store, body);
      expect(r.statusCode, HttpStatus.badRequest);
    }
    expect(store.plans.single.name, 'Old');
  });

  test(
    'an athlete and an admin without coach role get 403 and nothing changes',
    () async {
      final store = storeWithPlan();
      for (final ctx in [
        _ctx('club-a', {Rol.atleta}),
        _ctx('club-a', {Rol.adminClub}),
      ]) {
        final r = await _save(ctx, store, _validBody());
        expect(r.statusCode, HttpStatus.forbidden);
      }
      expect(store.plans.single.name, 'Old');
    },
  );

  group('club isolation', () {
    final store = _FakeStore()..catalog['ex-1'] = _exercise('ex-1');

    // The response echoes the plan, whose creation audit is kept from the stored one: that is the marker.
    testClubIsolation(
      'PUT /clubes/{clubId}/planes/{planId}',
      endpoint: (c) => savePlanEndpoint(c, 'shared-id', store: store),
      path: '/clubes/{clubId}/planes/shared-id',
      action: Accion.planificar,
      method: 'PUT',
      body: jsonEncode(_validBody()),
      seed: (clubId, marker) {
        store.plans.removeWhere(
          (p) => p.id == 'shared-id' && p.clubId == clubId,
        );
        store.plans.add(_stored(clubId, id: 'shared-id', createdBy: marker));
      },
    );
  });
}
