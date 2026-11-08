import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/plan/crear/crear.dart';
import 'package:maktub_backend/features/plan/crear/crear_store.dart';
import 'package:maktub_backend/features/plan/leer/leer.dart';
import 'package:maktub_backend/features/plan/leer/leer_store.dart';
import 'package:maktub_backend/features/plan/listar/listar.dart';
import 'package:maktub_backend/features/plan/listar/listar_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../support/club_isolation.dart';

class _Context extends Mock implements RequestContext {}

/// One in-memory collection that every use case of the slice sees through its own interface. Like Mongo,
/// it answers only for the club it is asked about.
class _FakeStore implements CreatePlanStore, ReadPlanStore, ListPlansStore {
  final all = <Plan>[];

  @override
  Future<void> insert(Plan plan) async => all.add(plan);

  @override
  Future<Plan?> plan(String clubId, String planId) async {
    for (final p in all) {
      if (p.clubId == clubId && p.id == planId) return p;
    }
    return null;
  }

  @override
  Future<List<Plan>> plans(String clubId) async => [
    for (final p in all)
      if (p.clubId == clubId) p,
  ];
}

final _t0 = DateTime.utc(2026, 11, 1, 10);

Plan _plan(
  String id,
  String clubId,
  String name, {
  PlanType type = PlanType.regular,
  List<WeekModel> models = const [],
  Auditoria? audit,
}) => Plan(
  id: id,
  clubId: clubId,
  name: name,
  type: type,
  weekModels: models,
  weekAssignment: models.isEmpty ? const [] : ['A', 'A', 'A', 'A'],
  auditoria: audit ?? Auditoria.nueva('coach-1', ahora: _t0),
);

ClubContext _ctx(String clubId, Set<Rol> roles, {String userId = 'coach-1'}) =>
    ClubContext(
      clubId: clubId,
      userId: userId,
      roles: roles,
      clubType: TipoClub.club,
    );

final _coachA = _ctx('club-a', {Rol.coach});
final _athleteA = _ctx('club-a', {Rol.atleta}, userId: 'u-1');
final _adminOnlyA = _ctx('club-a', {Rol.adminClub}, userId: 'u-2');
final _coachB = _ctx('club-b', {Rol.coach}, userId: 'coach-2');

Future<Response> _call(
  ClubContext ctx,
  Future<Response> Function(RequestContext) endpoint, {
  Object? body,
  String method = 'GET',
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

Future<Map<String, dynamic>> _json(Response r) async =>
    jsonDecode(await r.body()) as Map<String, dynamic>;

void main() {
  final fullPlan = _plan(
    'p1',
    'club-a',
    'Octubre',
    models: const [
      WeekModel(
        id: 'A',
        name: 'A',
        days: [
          PlanDay(
            name: 'Lunes',
            blocks: [
              PlanBlock(
                name: 'Fuerza',
                categoryId: 'cat-1',
                prescriptions: [
                  Prescription(
                    exerciseId: 'ex-1',
                    sets: [
                      PlanSet(reps: 5, pct: 80),
                      PlanSet(reps: 3, kg: 100),
                    ],
                    note: 'RPE 8',
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );

  group('create', () {
    Future<Response> create(ClubContext ctx, _FakeStore store, Object? body) =>
        _call(
          ctx,
          (c) => createPlanEndpoint(
            c,
            store: store,
            newId: () => 'new-id',
            now: () => _t0,
          ),
          body: body,
          method: 'POST',
        );

    test(
      'a coach creates a plan with name and type: 201, id and clubId',
      () async {
        final store = _FakeStore();
        final r = await create(_coachA, store, {
          'nombre': 'Ciclo 1',
          'tipo': 'test',
        });

        expect(r.statusCode, HttpStatus.created);
        final body = await _json(r);
        expect(body['id'], 'new-id');
        expect(body['clubId'], 'club-a');
        expect(body['nombre'], 'Ciclo 1');
        expect(body['tipo'], 'test');
        expect(body['modelosSemana'], isEmpty);
        expect(body['asignacion'], isEmpty);
        expect(body['auditoria']['creadoPor'], 'coach-1');
        expect(store.all.single.id, 'new-id');
        expect(store.all.single.clubId, 'club-a');
      },
    );

    test('the type defaults to regular and the name is trimmed', () async {
      final store = _FakeStore();
      final r = await create(_coachA, store, {'nombre': '  Ciclo  '});

      final body = await _json(r);
      expect(body['tipo'], 'regular');
      expect(body['nombre'], 'Ciclo');
    });

    test('a clubId sent by the client is ignored', () async {
      final store = _FakeStore();
      await create(_coachA, store, {'nombre': 'X', 'clubId': 'club-b'});

      expect(store.all.single.clubId, 'club-a');
    });

    test('a missing or blank name is 400 and nothing is stored', () async {
      final store = _FakeStore();
      for (final body in [
        <String, dynamic>{},
        {'nombre': '   '},
        {'nombre': 3},
      ]) {
        final r = await create(_coachA, store, body);
        expect(r.statusCode, HttpStatus.badRequest);
      }
      expect(store.all, isEmpty);
    });

    test('an unknown type is 400', () async {
      final store = _FakeStore();
      final r = await create(_coachA, store, {'nombre': 'X', 'tipo': 'otro'});

      expect(r.statusCode, HttpStatus.badRequest);
      expect(store.all, isEmpty);
    });

    test('an athlete and an admin without coach role get 403 and nothing is stored', () async {
      final store = _FakeStore();
      for (final ctx in [_athleteA, _adminOnlyA]) {
        final r = await create(ctx, store, {'nombre': 'X'});
        expect(r.statusCode, HttpStatus.forbidden);
      }
      expect(store.all, isEmpty);
    });
  });

  group('read', () {
    Future<Response> read(ClubContext ctx, _FakeStore store, String id) =>
        _call(ctx, (c) => readPlanEndpoint(c, id, store: store));

    test('a coach reads the whole plan, round-trip identical', () async {
      final store = _FakeStore()..all.add(fullPlan);
      final r = await read(_coachA, store, 'p1');

      expect(r.statusCode, HttpStatus.ok);
      expect(await _json(r), fullPlan.toJson());
    });

    test('an unknown id is 404', () async {
      final r = await read(_coachA, _FakeStore()..all.add(fullPlan), 'nope');

      expect(r.statusCode, HttpStatus.notFound);
    });

    test(
      'a plan of another club is 404 and its content is not returned',
      () async {
        final store = _FakeStore()..all.add(fullPlan);
        final r = await read(_coachB, store, 'p1');

        expect(r.statusCode, HttpStatus.notFound);
        expect(await r.body(), isNot(contains('Octubre')));
      },
    );

    test('an athlete gets 403 without the content', () async {
      final r = await read(_athleteA, _FakeStore()..all.add(fullPlan), 'p1');

      expect(r.statusCode, HttpStatus.forbidden);
      expect(await r.body(), isNot(contains('Octubre')));
    });
  });

  group('list', () {
    Future<Response> list(ClubContext ctx, _FakeStore store) =>
        _call(ctx, (c) => listPlansEndpoint(c, store: store));

    test(
      'returns one summary per plan, sorted by name ignoring case',
      () async {
        final store = _FakeStore()
          ..all.addAll([
            _plan('p3', 'club-a', 'Zeta'),
            fullPlan,
            _plan('p2', 'club-a', 'abril', type: PlanType.test),
            _plan('x1', 'club-b', 'Otro club'),
          ]);
        final r = await list(_coachA, store);

        expect(r.statusCode, HttpStatus.ok);
        final body = jsonDecode(await r.body()) as List;
        expect(
          [for (final p in body) (p as Map)['nombre']],
          ['abril', 'Octubre', 'Zeta'],
        );
        expect(body[0], {
          'id': 'p2',
          'nombre': 'abril',
          'tipo': 'test',
          'cantidadModelos': 0,
          'publicado': false,
          'cambiosSinPublicar': true,
          'actualizadoEn': _t0.toIso8601String(),
        });
        expect((body[1] as Map)['cantidadModelos'], 1);
      },
    );

    test(
      'actualizadoEn is the modification instant when there is one',
      () async {
        final modified = DateTime.utc(2026, 11, 5);
        final store = _FakeStore()
          ..all.add(
            _plan(
              'p1',
              'club-a',
              'A',
              audit: Auditoria.nueva(
                'coach-1',
                ahora: _t0,
              ).modificada('coach-1', ahora: modified),
            ),
          );
        final body =
            jsonDecode(await (await list(_coachA, store)).body()) as List;

        expect(
          (body.single as Map)['actualizadoEn'],
          modified.toIso8601String(),
        );
      },
    );

    test('equal names are ordered by id', () async {
      final store = _FakeStore()
        ..all.addAll([_plan('p2', 'club-a', 'A'), _plan('p1', 'club-a', 'A')]);
      final body =
          jsonDecode(await (await list(_coachA, store)).body()) as List;

      expect([for (final p in body) (p as Map)['id']], ['p1', 'p2']);
    });

    test('a club without plans gets an empty list', () async {
      final r = await list(_coachB, _FakeStore()..all.add(fullPlan));

      expect(jsonDecode(await r.body()), isEmpty);
    });

    test('an athlete gets 403', () async {
      final r = await list(_athleteA, _FakeStore()..all.add(fullPlan));

      expect(r.statusCode, HttpStatus.forbidden);
      expect(await r.body(), isNot(contains('Octubre')));
    });
  });

  group('club isolation', () {
    final store = _FakeStore();

    testClubIsolation(
      'GET /clubes/{clubId}/planes',
      endpoint: (c) => listPlansEndpoint(c, store: store),
      path: '/clubes/{clubId}/planes',
      action: Accion.planificar,
      seed: (clubId, marker) =>
          store.all.add(_plan('id-$marker', clubId, marker)),
    );

    // Both clubs hold a plan with the same id: each club's route must return its own.
    testClubIsolation(
      'GET /clubes/{clubId}/planes/{planId}',
      endpoint: (c) => readPlanEndpoint(c, 'shared-id', store: store),
      path: '/clubes/{clubId}/planes/shared-id',
      action: Accion.planificar,
      seed: (clubId, marker) {
        store.all.removeWhere((p) => p.id == 'shared-id' && p.clubId == clubId);
        store.all.add(_plan('shared-id', clubId, marker));
      },
    );

    // A create echoes the plan, so the new id is the marker the club's seed announced.
    final pending = <String, String>{};
    testClubIsolation(
      'POST /clubes/{clubId}/planes',
      // testClubIsolation expects a 200 for the allowed case, so the 201 is mapped to it here.
      endpoint: (c) async {
        final r = await createPlanEndpoint(
          c,
          store: _FakeStore(),
          newId: () => pending[c.read<ClubContext>().clubId]!,
        );
        return r.statusCode == HttpStatus.created
            ? Response(body: await r.body())
            : r;
      },
      path: '/clubes/{clubId}/planes',
      action: Accion.planificar,
      method: 'POST',
      body: '{"nombre": "created"}',
      seed: (clubId, marker) => pending[clubId] = marker,
    );
  });
}
