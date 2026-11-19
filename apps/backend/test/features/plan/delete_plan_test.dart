import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/plan/delete_plan/delete_plan.dart';
import 'package:maktub_backend/features/plan/delete_plan/delete_plan_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:test/test.dart';

class _Context extends Mock implements RequestContext {}

/// Plans by (club, id); like Mongo, it answers only for the club it is asked about.
class _FakeStore implements DeletePlanStore {
  _FakeStore(Iterable<(String, String)> plans, {this.creator = 'u-1', this.visibility = PlanVisibility.private})
    : plans = {...plans};

  final Set<(String, String)> plans;

  /// Who created every plan, and its visibility.
  final String creator;
  final PlanVisibility visibility;

  @override
  Future<Plan?> plan(String clubId, String planId) async => plans.contains((clubId, planId))
      ? Plan(
          id: planId,
          clubId: clubId,
          name: 'P',
          visibility: visibility,
          auditoria: Auditoria(creadoPor: creator, creadoEn: DateTime.utc(2026, 11, 19)),
        )
      : null;

  @override
  Future<bool> deletePlan(String clubId, String planId) async => plans.remove((clubId, planId));
}

ClubContext _ctx(String clubId, Set<Rol> roles) =>
    ClubContext(clubId: clubId, userId: 'u-1', roles: roles, clubType: TipoClub.club);

Future<Response> _delete(ClubContext ctx, _FakeStore store, String planId) async {
  final context = _Context();
  when(() => context.request).thenReturn(Request('DELETE', Uri.parse('http://localhost/x')));
  when(() => context.read<ClubContext>()).thenReturn(ctx);
  return await manejarErrores()((c) => deletePlanEndpoint(c, planId, store: store))(context);
}

void main() {
  group('endpoint', () {
    test('a coach deletes the plan: 204', () async {
      final store = _FakeStore([('club-a', 'p1')]);

      final r = await _delete(_ctx('club-a', {Rol.coach}), store, 'p1');

      expect(r.statusCode, HttpStatus.noContent);
      expect(store.plans, isEmpty);
    });

    test('another coach cannot delete a plan shared with them, even editable: 403 and it stays', () async {
      final store = _FakeStore([('club-a', 'p1')], creator: 'u-2', visibility: PlanVisibility.sharedEditable);

      final r = await _delete(_ctx('club-a', {Rol.coach}), store, 'p1');

      expect(r.statusCode, HttpStatus.forbidden);
      expect(store.plans, {('club-a', 'p1')});
    });

    test("another coach's private plan does not exist for them: 404 and it stays", () async {
      final store = _FakeStore([('club-a', 'p1')], creator: 'u-2');

      final r = await _delete(_ctx('club-a', {Rol.coach}), store, 'p1');

      expect(r.statusCode, HttpStatus.notFound);
      expect(store.plans, {('club-a', 'p1')});
    });

    test("a club admin who is not a coach can delete it too, even another coach's private plan", () async {
      final store = _FakeStore([('club-a', 'p1')], creator: 'u-2');

      final r = await _delete(_ctx('club-a', {Rol.adminClub}), store, 'p1');

      expect(r.statusCode, HttpStatus.noContent);
      expect(store.plans, isEmpty);
    });

    test('an athlete gets 403 and nothing is deleted', () async {
      final store = _FakeStore([('club-a', 'p1')]);

      final r = await _delete(_ctx('club-a', {Rol.atleta}), store, 'p1');

      expect(r.statusCode, HttpStatus.forbidden);
      expect(store.plans, {('club-a', 'p1')});
    });

    test('a plan of another club is 404 and stays', () async {
      final store = _FakeStore([('club-a', 'p1')]);

      final r = await _delete(_ctx('club-b', {Rol.coach}), store, 'p1');

      expect(r.statusCode, HttpStatus.notFound);
      expect(store.plans, {('club-a', 'p1')});
    });

    test('deleting twice is 404 the second time', () async {
      final store = _FakeStore([('club-a', 'p1')]);
      final coach = _ctx('club-a', {Rol.coach});

      await _delete(coach, store, 'p1');
      final r = await _delete(coach, store, 'p1');

      expect(r.statusCode, HttpStatus.notFound);
    });
  });

  test('only coaches and club admins may delete plans', () {
    bool can(Set<Rol> roles, [TipoClub type = TipoClub.club]) => puede(roles, Accion.deletePlan, type);

    expect(can({Rol.coach}), isTrue);
    expect(can({Rol.adminClub}), isTrue);
    expect(can({Rol.atleta}), isFalse);
    expect(can({Rol.atleta}, TipoClub.personal), isFalse);
  });

  group('Mongo store', () {
    Db? db;
    final name = 'maktub_test_e89_${DateTime.now().microsecondsSinceEpoch}';

    setUpAll(() async {
      try {
        final base = Platform.environment['TEST_MONGO_URL'] ?? 'mongodb://localhost:27017';
        db = await abrirMongo('$base/$name');
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
          markTestSkipped('MongoDB not available');
          return;
        }
        await body();
      });
    }

    Future<void> clear() async {
      for (final c in [
        Colecciones.planes,
        Colecciones.asignaciones,
        Colecciones.sesiones,
        Colecciones.registros,
        Colecciones.tiemposBloque,
      ]) {
        await db!.collection(c).remove({});
      }
    }

    mongoTest('deletes the plan and its assignments, keeps what was recorded', () async {
      final plans = db!.collection(Colecciones.planes);
      final assignments = db!.collection(Colecciones.asignaciones);
      await clear();
      // A plan's id is its document's `_id`, as `aDocumento` stores it.
      await plans.insertMany([
        {'_id': 'p1', 'clubId': 'club-a'},
        {'_id': 'p2', 'clubId': 'club-a'},
        {'_id': 'p1-b', 'clubId': 'club-b'},
      ]);
      await assignments.insertMany([
        {'_id': 'a1', 'clubId': 'club-a', 'planId': 'p1', 'estado': 'terminada'},
        {'_id': 'a2', 'clubId': 'club-a', 'planId': 'p1', 'estado': 'activa'},
        {'_id': 'a3', 'clubId': 'club-a', 'planId': 'p2', 'estado': 'activa'},
        {'_id': 'a4', 'clubId': 'club-b', 'planId': 'p1', 'estado': 'activa'},
      ]);
      await db!.collection(Colecciones.sesiones).insertOne({'_id': 's1', 'clubId': 'club-a', 'planId': 'p1', 'asignacionId': 'a1'});
      await db!.collection(Colecciones.registros).insertOne({'_id': 'r1', 'clubId': 'club-a', 'sesionId': 's1'});
      await db!.collection(Colecciones.tiemposBloque).insertOne({'_id': 't1', 'clubId': 'club-a', 'sesionId': 's1'});

      expect(await MongoDeletePlanStore(db!).deletePlan('club-a', 'p1'), isTrue);

      expect([for (final d in await plans.find().toList()) d['_id']], unorderedEquals(['p2', 'p1-b']));
      expect([for (final d in await assignments.find().toList()) d['_id']], unorderedEquals(['a3', 'a4']));
      expect(await db!.collection(Colecciones.sesiones).count(), 1);
      expect(await db!.collection(Colecciones.registros).count(), 1);
      expect(await db!.collection(Colecciones.tiemposBloque).count(), 1);
    });

    mongoTest('a plan of another club, or a missing one, deletes nothing', () async {
      final plans = db!.collection(Colecciones.planes);
      final assignments = db!.collection(Colecciones.asignaciones);
      await clear();
      await plans.insertOne({'_id': 'p1', 'clubId': 'club-a'});
      await assignments.insertOne({'_id': 'a1', 'clubId': 'club-a', 'planId': 'p1'});
      final store = MongoDeletePlanStore(db!);

      expect(await store.deletePlan('club-b', 'p1'), isFalse);
      expect(await store.deletePlan('club-a', 'nope'), isFalse);

      expect(await plans.count(), 1);
      expect(await assignments.count(), 1);
    });
  });
}
