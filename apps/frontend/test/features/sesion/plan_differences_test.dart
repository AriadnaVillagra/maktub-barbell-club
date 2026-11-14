import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/sesion/domain/guided_session.dart';
import 'package:maktub_frontend/features/sesion/domain/plan_differences.dart';

final _t0 = DateTime.utc(2026, 11, 18, 10);

const _two = [PlanSet(reps: 5, pct: 80), PlanSet(reps: 5, pct: 80)];

const _day = PlanDay(
  blocks: [
    // 0: no sets.
    PlanBlock(name: 'Movilidad', categoryId: 'estiramiento'),
    // 1: two sets.
    PlanBlock(
      name: 'Principal',
      categoryId: 'primario',
      prescriptions: [Prescription(exerciseId: 'sq', sets: _two)],
    ),
  ],
);

SetRecord _record(
  String athlete,
  int set, {
  double? kg = 80,
  int? reps = 5,
  bool done = true,
}) => SetRecord(
  id: '$athlete-$set',
  clubId: 'c1',
  sessionId: 's1',
  athleteId: athlete,
  exerciseId: 'sq',
  exerciseName: 'Sentadilla',
  blockIndex: 1,
  prescriptionIndex: 0,
  setIndex: set,
  done: done,
  kg: kg,
  reps: reps,
  writtenBy: 'u',
  auditoria: Auditoria.nueva('u', ahora: _t0),
);

ProposedSet _proposed(int set, double kg) => ProposedSet(
  blockIndex: 1,
  prescriptionIndex: 0,
  setIndex: set,
  exerciseId: 'sq',
  kg: kg,
);

/// The day with the first block skipped and the second one closed as [close] says.
GuidedSession _day2(GuidedSession Function(GuidedSession) close) => close(
  GuidedSession.choosing(_day, const ['ari', 'andi'])
      .begin(now: _t0)
      .skipBlock(now: _t0)
      .startBlock(const {}, now: _t0),
);

GuidedSession _interrupted(GuidedSession g) => g.interruptBlock(now: _t0);

List<PlanDifference> _diff(
  GuidedSession g,
  List<SetRecord> records, {
  Map<String, List<ProposedSet>>? proposed,
}) => planDifferences(
  guided: g,
  records: records,
  proposed:
      proposed ??
      {
        for (final a in ['ari', 'andi']) a: [_proposed(0, 80), _proposed(1, 80)],
      },
);

void main() {
  final everything = [
    for (final a in ['ari', 'andi'])
      for (var s = 0; s < 2; s++) _record(a, s),
  ];

  test('a skipped block without sets is "no se hizo"', () {
    final d = _diff(_day2(_interrupted), everything);

    expect(d.map((x) => x.kind), [PlanDifferenceKind.blockSkipped]);
    expect(d.single.blockName, 'Movilidad');
  });

  test('an athlete with none of the sets "did not do it"', () {
    final d = _diff(_day2(_interrupted), [
      for (var s = 0; s < 2; s++) _record('ari', s),
    ]).where((x) => x.kind != PlanDifferenceKind.blockSkipped);

    expect(d.single.kind, PlanDifferenceKind.notDone);
    expect(d.single.athleteId, 'andi');
    expect(d.single.prescriptionIndex, 0);
  });

  test('a record that is not done does not count', () {
    final d = _diff(_day2(_interrupted), [
      _record('ari', 0, done: false),
      for (var s = 0; s < 2; s++) _record('andi', s),
    ]).where((x) => x.kind != PlanDifferenceKind.blockSkipped);

    expect(d.single.kind, PlanDifferenceKind.notDone);
    expect(d.single.athleteId, 'ari');
  });

  test('some of the sets reads "X of N"', () {
    final d = _diff(_day2(_interrupted), [
      _record('ari', 1),
      for (var s = 0; s < 2; s++) _record('andi', s),
    ]).where((x) => x.kind != PlanDifferenceKind.blockSkipped);

    expect(d.single.kind, PlanDifferenceKind.someSets);
    expect((d.single.done, d.single.planned), (1, 2));
  });

  test('a set done with other kilos or reps shows both', () {
    final d = _diff(
      _day2(_interrupted),
      [
        _record('ari', 0, kg: 77.5, reps: 4),
        _record('ari', 1),
        for (var s = 0; s < 2; s++) _record('andi', s),
      ],
    ).where((x) => x.kind != PlanDifferenceKind.blockSkipped).single;

    expect(d.kind, PlanDifferenceKind.changedSet);
    expect(d.athleteId, 'ari');
    expect(d.setNumber, 1);
    expect((d.kg, d.reps), (77.5, 4));
    expect((d.planKg, d.planReps), (80, 5));
  });

  test('kilos are compared with what the server proposed for that athlete', () {
    final proposed = {
      'ari': [_proposed(0, 80), _proposed(1, 80)],
      'andi': [_proposed(0, 64), _proposed(1, 64)],
    };
    final records = [
      for (var s = 0; s < 2; s++) _record('ari', s),
      for (var s = 0; s < 2; s++) _record('andi', s, kg: 64),
    ];

    expect(
      _diff(_day2(_interrupted), records, proposed: proposed)
          .where((x) => x.kind != PlanDifferenceKind.blockSkipped),
      isEmpty,
    );
  });

  test('kilos that were not proposed or not recorded are not compared', () {
    final records = [
      for (final a in ['ari', 'andi'])
        for (var s = 0; s < 2; s++) _record(a, s, kg: null),
    ];

    expect(
      _diff(_day2(_interrupted), records)
          .where((x) => x.kind != PlanDifferenceKind.blockSkipped),
      isEmpty,
    );
    expect(
      _diff(_day2(_interrupted), everything, proposed: const {})
          .where((x) => x.kind != PlanDifferenceKind.blockSkipped),
      isEmpty,
    );
  });

  test('a block not reached yet is not compared', () {
    final g = GuidedSession.choosing(_day, const ['ari']).begin(now: _t0);

    expect(_diff(g, const []), isEmpty);
  });
}
