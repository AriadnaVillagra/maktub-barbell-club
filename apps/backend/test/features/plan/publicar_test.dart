import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/plan/guardar/guardar.dart';
import 'package:maktub_backend/features/plan/guardar/guardar_store.dart';
import 'package:maktub_backend/features/plan/listar/listar.dart';
import 'package:maktub_backend/features/plan/listar/listar_store.dart';
import 'package:maktub_backend/features/plan/publicar/publicar.dart';
import 'package:maktub_backend/features/plan/publicar/publicar_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

class _Context extends Mock implements RequestContext {}

/// One in-memory collection seen through the three slices' interfaces, like Mongo would.
class _FakeStore implements PublishPlanStore, SavePlanStore, ListPlansStore {
  final stored = <Plan>[];
  final catalog = <String, Exercise>{};

  /// Simulates a save that lands between the publish's read and its write.
  void Function()? beforePublishWrite;
  bool failOnPublish = false;

  @override
  Future<Plan?> plan(String clubId, String planId) async {
    for (final p in stored) {
      if (p.clubId == clubId && p.id == planId) return p;
    }
    return null;
  }

  @override
  Future<List<Plan>> plans(String clubId) async => [
    for (final p in stored)
      if (p.clubId == clubId) p,
  ];

  @override
  Future<Map<String, Exercise>> exercises(String clubId) async => catalog;

  @override
  Future<bool> replace(Plan plan) async {
    final i = stored.indexWhere(
      (p) => p.clubId == plan.clubId && p.id == plan.id,
    );
    if (i < 0) return false;
    // Like the Mongo store: the stored published copy is kept.
    stored[i] = Plan(
      id: plan.id,
      clubId: plan.clubId,
      name: plan.name,
      type: plan.type,
      weekModels: plan.weekModels,
      weekAssignment: plan.weekAssignment,
      published: stored[i].published,
      auditoria: plan.auditoria,
    );
    return true;
  }

  @override
  Future<bool> publish(
    String clubId,
    String planId,
    PublishedPlan copy, {
    required DateTime? savedAt,
  }) async {
    beforePublishWrite?.call();
    if (failOnPublish) throw StateError('write failed');
    final i = stored.indexWhere((p) => p.clubId == clubId && p.id == planId);
    if (i < 0 || stored[i].auditoria.modificadoEn != savedAt) return false;
    final p = stored[i];
    stored[i] = Plan(
      id: p.id,
      clubId: p.clubId,
      name: p.name,
      type: p.type,
      weekModels: p.weekModels,
      weekAssignment: p.weekAssignment,
      published: copy,
      auditoria: p.auditoria,
    );
    return true;
  }
}

final _t0 = DateTime.utc(2026, 11, 1, 10);
final _t1 = DateTime.utc(2026, 11, 6, 9);
final _t2 = DateTime.utc(2026, 11, 7, 9);

Exercise _exercise(String id) => Exercise(
  id: id,
  clubId: 'plataforma',
  name: id,
  categoryIds: const ['cat-1'],
  metrics: const [Metric.reps, Metric.loadPctRm],
  auditoria: Auditoria.nueva('sys', ahora: _t0),
);

List<WeekModel> _models({int pct = 80, String blockName = 'Fuerza'}) => [
  WeekModel(
    id: 'A',
    name: 'A',
    days: [
      PlanDay(
        name: 'Lunes',
        blocks: [
          PlanBlock(
            name: blockName,
            categoryId: 'cat-1',
            prescriptions: [
              Prescription(
                exerciseId: 'ex-1',
                sets: [PlanSet(reps: 5, pct: pct.toDouble())],
              ),
            ],
          ),
        ],
      ),
    ],
  ),
];

Plan _plan(
  String clubId, {
  String id = 'p1',
  String createdBy = 'coach-1',
  List<WeekModel>? models,
  PublishedPlan? published,
}) => Plan(
  id: id,
  clubId: clubId,
  name: 'Octubre',
  weekModels: models ?? _models(),
  weekAssignment: const ['A', 'A', 'A', 'A'],
  published: published,
  auditoria: Auditoria.nueva(createdBy, ahora: _t0),
);

PublishedPlan _published({String by = 'coach-0', int pct = 70}) =>
    PublishedPlan(
      weekModels: _models(pct: pct),
      weekAssignment: const ['A', 'A', 'A', 'A'],
      publishedAt: _t0,
      publishedBy: by,
    );

ClubContext _ctx(String clubId, Set<Rol> roles, {String userId = 'coach-2'}) =>
    ClubContext(
      clubId: clubId,
      userId: userId,
      roles: roles,
      clubType: TipoClub.club,
    );

Future<Response> _call(
  ClubContext ctx,
  Future<Response> Function(RequestContext) endpoint, {
  Object? body,
  String method = 'POST',
}) async {
  final context = _Context();
  when(() => context.request).thenReturn(
    Request(
      method,
      Uri.parse('http://localhost/x'),
      body: body == null ? null : jsonEncode(body),
    ),
  );
  when(() => context.read<ClubContext>()).thenReturn(ctx);
  return manejarErrores()(endpoint)(context);
}

Future<Response> _publish(
  ClubContext ctx,
  _FakeStore store, {
  String planId = 'p1',
}) => _call(
  ctx,
  (c) => publishPlanEndpoint(c, planId, store: store, now: () => _t2),
);

Future<Map<String, dynamic>> _json(Response r) async =>
    jsonDecode(await r.body()) as Map<String, dynamic>;

void main() {
  final coachA = _ctx('club-a', {Rol.coach});

  _FakeStore storeWith(Plan plan) => _FakeStore()
    ..stored.add(plan)
    ..catalog['ex-1'] = _exercise('ex-1');

  group('publish', () {
    test('copies the saved content with date and author', () async {
      final store = storeWith(_plan('club-a'));
      final r = await _publish(coachA, store);

      expect(r.statusCode, HttpStatus.ok);
      final published = store.stored.single.published!;
      expect(published.publishedAt, _t2);
      expect(published.publishedBy, 'coach-2');
      expect(published.weekAssignment, ['A', 'A', 'A', 'A']);
      expect(
        published.weekModels.map((m) => m.toJson()),
        store.stored.single.weekModels.map((m) => m.toJson()),
      );
      expect(store.stored.single.hasUnpublishedChanges, isFalse);
      final body = await _json(r);
      expect(body['publicado']['publicadoPor'], 'coach-2');
      expect(body['publicado']['publicadoEn'], _t2.toIso8601String());
    });

    test('republishing replaces the previous version', () async {
      final store = storeWith(_plan('club-a', published: _published()));
      final r = await _publish(coachA, store);

      expect(r.statusCode, HttpStatus.ok);
      expect(store.stored.single.published!.publishedBy, 'coach-2');
      expect(
        store
            .stored
            .single
            .published!
            .weekModels
            .single
            .days
            .single
            .blocks
            .single
            .prescriptions
            .single
            .sets
            .single
            .pct,
        80,
      );
    });

    test('a plan with any problem is 422 with problemas, and the previous version stays', () async {
      final previous = _published();
      // A draft that save accepts but publishing does not: a set without percentage.
      final store = storeWith(
        _plan('club-a', models: _models(pct: 0), published: previous),
      );
      final r = await _publish(coachA, store);

      expect(r.statusCode, HttpStatus.unprocessableEntity);
      final json = await _json(r);
      expect(json['error'], isA<String>());
      expect(json['problemas'], isNotEmpty);
      expect(json['problemas'].first['codigo'], isA<String>());
      expect(store.stored.single.published!.toJson(), previous.toJson());
    });

    test('a plan without week models is 422 and is not published', () async {
      final store = storeWith(
        Plan(
          id: 'p1',
          clubId: 'club-a',
          name: 'Vacío',
          auditoria: Auditoria.nueva('coach-1', ahora: _t0),
        ),
      );
      final r = await _publish(coachA, store);

      expect(r.statusCode, HttpStatus.unprocessableEntity);
      expect(store.stored.single.published, isNull);
    });

    test('a failing write leaves the previous version intact', () async {
      final previous = _published();
      final store = storeWith(_plan('club-a', published: previous))
        ..failOnPublish = true;
      final r = await _publish(coachA, store);

      expect(r.statusCode, HttpStatus.internalServerError);
      expect(store.stored.single.published!.toJson(), previous.toJson());
    });

    test(
      'a save between the read and the write is 409 and nothing is published',
      () async {
        final store = storeWith(_plan('club-a'));
        store.beforePublishWrite = () {
          final p = store.stored.single;
          store.stored[0] = Plan(
            id: p.id,
            clubId: p.clubId,
            name: p.name,
            weekModels: p.weekModels,
            weekAssignment: p.weekAssignment,
            auditoria: p.auditoria.modificada('coach-3', ahora: _t1),
          );
        };
        final r = await _publish(coachA, store);

        expect(r.statusCode, HttpStatus.conflict);
        expect((await _json(r))['error'], isA<String>());
        expect(store.stored.single.published, isNull);
      },
    );

    test('an unknown plan is 404', () async {
      final r = await _publish(
        coachA,
        storeWith(_plan('club-a')),
        planId: 'zz',
      );

      expect(r.statusCode, HttpStatus.notFound);
    });

    test('a plan of another club is 404 and is not published', () async {
      final store = storeWith(_plan('club-a'));
      final r = await _publish(_ctx('club-b', {Rol.coach}), store);

      expect(r.statusCode, HttpStatus.notFound);
      expect(store.stored.single.published, isNull);
    });

    test('an athlete and an admin without coach role get 403', () async {
      final store = storeWith(_plan('club-a'));
      for (final ctx in [
        _ctx('club-a', {Rol.atleta}),
        _ctx('club-a', {Rol.adminClub}),
      ]) {
        final r = await _publish(ctx, store);
        expect(r.statusCode, HttpStatus.forbidden);
      }
      expect(store.stored.single.published, isNull);
    });
  });

  group('save keeps the published version', () {
    Json body() => {
      'nombre': 'Octubre',
      'tipo': 'regular',
      'modelosSemana': [for (final m in _models(pct: 90)) m.toJson()],
      'asignacion': ['A', 'A', 'A', 'A'],
    };

    Future<Response> save(_FakeStore store, Json b) => _call(
      _ctx('club-a', {Rol.coach}),
      (c) => savePlanEndpoint(c, 'p1', store: store, now: () => _t1),
      body: b,
      method: 'PUT',
    );

    test(
      'saving a published plan leaves the published copy as it was',
      () async {
        final previous = _published();
        final store = storeWith(_plan('club-a', published: previous));
        final r = await save(store, body());

        expect(r.statusCode, HttpStatus.ok);
        final saved = store.stored.single;
        expect(saved.published!.toJson(), previous.toJson());
        expect(saved.hasUnpublishedChanges, isTrue);
        expect((await _json(r))['publicado'], previous.toJson());
      },
    );

    test('a publicado forged in the body is ignored', () async {
      final previous = _published();
      final store = storeWith(_plan('club-a', published: previous));
      await save(store, {
        ...body(),
        'publicado': _published(by: 'evil', pct: 99).toJson(),
      });
      expect(store.stored.single.published!.publishedBy, 'coach-0');
      expect(store.stored.single.published!.toJson(), previous.toJson());

      // And it cannot publish a plan that was never published.
      final never = storeWith(_plan('club-a'));
      await save(never, {...body(), 'publicado': _published().toJson()});
      expect(never.stored.single.published, isNull);
    });

    test('a plan that was never published stays so after saving', () async {
      final store = storeWith(_plan('club-a'));
      final r = await save(store, body());

      expect(r.statusCode, HttpStatus.ok);
      expect((await _json(r)).containsKey('publicado'), isFalse);
    });
  });

  group('list', () {
    test(
      'tells whether each plan is published and has unpublished changes',
      () async {
        final store = _FakeStore()
          ..stored.addAll([
            _plan('club-a', id: 'draft'),
            _plan(
              'club-a',
              id: 'live',
              published: PublishedPlan(
                weekModels: _models(),
                weekAssignment: const ['A', 'A', 'A', 'A'],
                publishedAt: _t0,
                publishedBy: 'c',
              ),
            ),
            _plan('club-a', id: 'edited', published: _published()),
          ]);
        final r = await _call(
          coachA,
          (c) => listPlansEndpoint(c, store: store),
          method: 'GET',
        );
        final byId = <String, Map<String, dynamic>>{
          for (final e in jsonDecode(await r.body()) as List)
            (e as Map<String, dynamic>)['id'] as String: e,
        };

        expect(byId['draft']!['publicado'], isFalse);
        expect(byId['draft']!['cambiosSinPublicar'], isTrue);
        expect(byId['live']!['publicado'], isTrue);
        expect(byId['live']!['cambiosSinPublicar'], isFalse);
        expect(byId['edited']!['publicado'], isTrue);
        expect(byId['edited']!['cambiosSinPublicar'], isTrue);
      },
    );
  });

  group('club isolation', () {
    final store = _FakeStore()..catalog['ex-1'] = _exercise('ex-1');

    // The response echoes the plan, whose creation audit comes from the stored one: that is the marker.
    testClubIsolation(
      'POST /clubes/{clubId}/planes/{planId}/publicar',
      endpoint: (c) => publishPlanEndpoint(c, 'shared-id', store: store),
      path: '/clubes/{clubId}/planes/shared-id/publicar',
      action: Accion.planificar,
      method: 'POST',
      seed: (clubId, marker) {
        store.stored.removeWhere(
          (p) => p.id == 'shared-id' && p.clubId == clubId,
        );
        store.stored.add(_plan(clubId, id: 'shared-id', createdBy: marker));
      },
    );
  });
}
