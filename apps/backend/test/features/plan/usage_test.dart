import 'dart:io';

import 'package:maktub_backend/features/plan/usage/usage.dart';
import 'package:maktub_backend/features/plan/usage/usage_store.dart';
import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:test/test.dart';

Plan _plan(
  String id,
  String clubId, {
  String? exerciseId,
  String? blockTimer,
  String? prescriptionTimer,
}) => Plan(
  id: id,
  clubId: clubId,
  name: 'Plan $id',
  weekModels: [
    WeekModel(
      id: 'A',
      name: 'A',
      days: [
        PlanDay(
          blocks: [
            PlanBlock(
              name: 'Main',
              timerId: blockTimer,
              prescriptions: [
                Prescription(
                  exerciseId: exerciseId,
                  timerId: prescriptionTimer,
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
  weekAssignment: const ['A', 'A', 'A', 'A'],
  auditoria: Auditoria.nueva('coach', ahora: DateTime.utc(2026, 11, 1)),
);

/// In-memory version of the same question, honoring the club scope like the Mongo one.
class _FakeUsageStore implements PlanUsageStore {
  final plans = <Plan>[];

  Iterable<Plan> _scoped(String? clubId) =>
      plans.where((p) => clubId == null || p.clubId == clubId);

  @override
  Future<bool> exerciseInPlans(String? clubId, String exerciseId) async =>
      _scoped(clubId).any(
        (p) => p.weekModels.any(
          (w) => w.days.any(
            (d) => d.blocks.any(
              (b) => b.prescriptions.any((x) => x.exerciseId == exerciseId),
            ),
          ),
        ),
      );

  @override
  Future<bool> timerInPlans(String? clubId, String timerId) async =>
      _scoped(clubId).any(
        (p) => p.weekModels.any(
          (w) => w.days.any(
            (d) => d.blocks.any(
              (b) =>
                  b.timerId == timerId ||
                  b.prescriptions.any((x) => x.timerId == timerId),
            ),
          ),
        ),
      );
}

/// Behavior shared by the fake store and the real Mongo store.
void _usageCases(Future<PlanUsageStore> Function(List<Plan> plans) build) {
  Future<bool> exercise(List<Plan> plans, String clubId, String id) async =>
      PlanExerciseUsage(await build(plans)).isUsed(clubId, id);
  Future<bool> timer(List<Plan> plans, String clubId, String id) async =>
      PlanTimerUsage(await build(plans)).isUsed(clubId, id);

  test('an exercise in a prescription of a club plan is in use', () async {
    expect(
      await exercise([_plan('p1', 'a', exerciseId: 'e1')], 'a', 'e1'),
      isTrue,
    );
  });

  test('an exercise no plan refers to is not in use', () async {
    expect(
      await exercise([_plan('p1', 'a', exerciseId: 'e2')], 'a', 'e1'),
      isFalse,
    );
    expect(await exercise([], 'a', 'e1'), isFalse);
  });

  test(
    'a plan of another club does not make a club exercise or timer in use',
    () async {
      final plans = [_plan('p1', 'b', exerciseId: 'e1', blockTimer: 't1')];
      expect(await exercise(plans, 'a', 'e1'), isFalse);
      expect(await timer(plans, 'a', 't1'), isFalse);
    },
  );

  test('a block timer is in use', () async {
    expect(
      await timer([_plan('p1', 'a', blockTimer: 't1')], 'a', 't1'),
      isTrue,
    );
  });

  test('a prescription timer is in use', () async {
    expect(
      await timer([_plan('p1', 'a', prescriptionTimer: 't1')], 'a', 't1'),
      isTrue,
    );
  });

  test('a timer no plan refers to is not in use', () async {
    expect(
      await timer(
        [_plan('p1', 'a', blockTimer: 't2', prescriptionTimer: 't3')],
        'a',
        't1',
      ),
      isFalse,
    );
  });

  test(
    'an exercise is not mistaken for a timer with the same id, nor the reverse',
    () async {
      final plans = [_plan('p1', 'a', exerciseId: 'x', blockTimer: 'y')];
      expect(await timer(plans, 'a', 'x'), isFalse);
      expect(await exercise(plans, 'a', 'y'), isFalse);
    },
  );

  test(
    'a platform base item is in use when a plan of any club refers to it',
    () async {
      final plans = [
        _plan('p1', 'b', exerciseId: 'e1', prescriptionTimer: 't1'),
      ];
      expect(await exercise(plans, clubPlataforma, 'e1'), isTrue);
      expect(await timer(plans, clubPlataforma, 't1'), isTrue);
      expect(await exercise(plans, clubPlataforma, 'e9'), isFalse);
    },
  );
}

Future<bool> _mongoAvailable() async {
  try {
    final socket = await Socket.connect(
      'localhost',
      27017,
      timeout: const Duration(seconds: 1),
    );
    await socket.close();
    return true;
  } on Object {
    return false;
  }
}

void main() {
  group('with a fake store', () {
    _usageCases((plans) async => _FakeUsageStore()..plans.addAll(plans));
  });

  group('against MongoDB', () {
    late Db db;
    var available = false;

    setUpAll(() async {
      available = await _mongoAvailable();
      if (!available) return;
      db = await abrirMongo('mongodb://localhost:27017/maktub_test_plan_usage');
      await asegurarIndices(db);
    });

    tearDownAll(() async {
      if (!available) return;
      await db.drop();
      await db.close();
    });

    _usageCases((plans) async {
      if (!available) {
        markTestSkipped('MongoDB is not reachable on localhost:27017');
        // Falls back to the fake so the body still runs; the skip marks the Mongo run as not exercised.
        return _FakeUsageStore()..plans.addAll(plans);
      }
      final collection = db.collection(Colecciones.planes);
      await collection.deleteMany({});
      for (final p in plans) {
        await collection.insertOne(aDocumento(p.toJson()));
      }
      return MongoPlanUsageStore(db);
    });
  });
}
