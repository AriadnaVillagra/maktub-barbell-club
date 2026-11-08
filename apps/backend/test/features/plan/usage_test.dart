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

Wod _wod(
  String id,
  String clubId, {
  String? exerciseId,
  String? wodTimer,
  String? prescriptionTimer,
}) => Wod(
  id: id,
  clubId: clubId,
  name: 'WoD $id',
  timerId: wodTimer,
  prescriptions: [
    Prescription(exerciseId: exerciseId, timerId: prescriptionTimer),
  ],
  auditoria: Auditoria.nueva('coach', ahora: DateTime.utc(2026, 11, 1)),
);

/// In-memory version of the same question, honoring the club scope like the Mongo one.
class _FakeUsageStore implements PlanUsageStore {
  final plans = <Plan>[];
  final wods = <Wod>[];

  Iterable<Plan> _scoped(String? clubId) =>
      plans.where((p) => clubId == null || p.clubId == clubId);

  List<WeekModel> _models(Plan p) => [
    ...p.weekModels,
    ...?p.published?.weekModels,
  ];

  @override
  Future<bool> exerciseInPlans(String? clubId, String exerciseId) async =>
      _scoped(clubId).any(
        (p) => _models(p).any(
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
        (p) => _models(p).any(
          (w) => w.days.any(
            (d) => d.blocks.any(
              (b) =>
                  b.timerId == timerId ||
                  b.prescriptions.any((x) => x.timerId == timerId),
            ),
          ),
        ),
      );

  Iterable<Wod> _scopedWods(String? clubId) =>
      wods.where((w) => clubId == null || w.clubId == clubId);

  @override
  Future<bool> exerciseInWods(String? clubId, String exerciseId) async =>
      _scopedWods(clubId)
          .any((w) => w.prescriptions.any((x) => x.exerciseId == exerciseId));

  @override
  Future<bool> timerInWods(String? clubId, String timerId) async =>
      _scopedWods(clubId).any(
        (w) =>
            w.timerId == timerId ||
            w.prescriptions.any((x) => x.timerId == timerId),
      );
}

/// Behavior shared by the fake store and the real Mongo store.
void _usageCases(
  Future<PlanUsageStore> Function(List<Plan> plans, List<Wod> wods) build,
) {
  Future<bool> exercise(
    List<Plan> plans,
    String clubId,
    String id, [
    List<Wod> wods = const [],
  ]) async => PlanExerciseUsage(await build(plans, wods)).isUsed(clubId, id);
  Future<bool> timer(
    List<Plan> plans,
    String clubId,
    String id, [
    List<Wod> wods = const [],
  ]) async => PlanTimerUsage(await build(plans, wods)).isUsed(clubId, id);

  Plan onlyPublished(Plan source) => Plan(
    id: source.id,
    clubId: source.clubId,
    name: source.name,
    auditoria: source.auditoria,
    published: PublishedPlan(
      weekModels: source.weekModels,
      weekAssignment: source.weekAssignment,
      publishedAt: DateTime.utc(2026, 11, 2),
      publishedBy: 'coach',
    ),
  );

  test('what only the published copy still uses is in use', () async {
    final plan = onlyPublished(
      _plan(
        'p1',
        'a',
        exerciseId: 'e1',
        blockTimer: 't1',
        prescriptionTimer: 't2',
      ),
    );
    expect(await exercise([plan], 'a', 'e1'), isTrue);
    expect(await timer([plan], 'a', 't1'), isTrue);
    expect(await timer([plan], 'a', 't2'), isTrue);
    expect(await exercise([plan], 'b', 'e1'), isFalse);
  });

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

  test('an exercise in a prescription of a club WoD is in use', () async {
    final wods = [_wod('w1', 'a', exerciseId: 'e1')];
    expect(await exercise([], 'a', 'e1', wods), isTrue);
    expect(await exercise([], 'a', 'e2', wods), isFalse);
  });

  test('a WoD timer and a WoD prescription timer are in use', () async {
    final wods = [
      _wod('w1', 'a', wodTimer: 't1'),
      _wod('w2', 'a', prescriptionTimer: 't2'),
    ];
    expect(await timer([], 'a', 't1', wods), isTrue);
    expect(await timer([], 'a', 't2', wods), isTrue);
    expect(await timer([], 'a', 't3', wods), isFalse);
  });

  test(
    'a WoD of another club does not make a club exercise or timer in use',
    () async {
      final wods = [_wod('w1', 'b', exerciseId: 'e1', wodTimer: 't1')];
      expect(await exercise([], 'a', 'e1', wods), isFalse);
      expect(await timer([], 'a', 't1', wods), isFalse);
    },
  );

  test(
    'a platform base item is in use when a WoD of any club refers to it',
    () async {
      final wods = [_wod('w1', 'b', exerciseId: 'e1', prescriptionTimer: 't1')];
      expect(await exercise([], clubPlataforma, 'e1', wods), isTrue);
      expect(await timer([], clubPlataforma, 't1', wods), isTrue);
      expect(await timer([], clubPlataforma, 't9', wods), isFalse);
    },
  );

  test('an exercise is not mistaken for a timer in a WoD', () async {
    final wods = [_wod('w1', 'a', exerciseId: 'x', wodTimer: 'y')];
    expect(await timer([], 'a', 'x', wods), isFalse);
    expect(await exercise([], 'a', 'y', wods), isFalse);
  });
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
    _usageCases(
      (plans, wods) async => _FakeUsageStore()
        ..plans.addAll(plans)
        ..wods.addAll(wods),
    );
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

    _usageCases((plans, wods) async {
      if (!available) {
        markTestSkipped('MongoDB is not reachable on localhost:27017');
        // Falls back to the fake so the body still runs; the skip marks the Mongo run as not exercised.
        return _FakeUsageStore()
          ..plans.addAll(plans)
          ..wods.addAll(wods);
      }
      final planCollection = db.collection(Colecciones.planes);
      await planCollection.deleteMany({});
      for (final p in plans) {
        await planCollection.insertOne(aDocumento(p.toJson()));
      }
      final wodCollection = db.collection(Colecciones.wods);
      await wodCollection.deleteMany({});
      for (final w in wods) {
        await wodCollection.insertOne(aDocumento(w.toJson()));
      }
      return MongoPlanUsageStore(db);
    });
  });
}
