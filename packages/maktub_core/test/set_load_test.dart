import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

final _audit = Auditoria.nueva('coach', ahora: DateTime.utc(2026, 11, 1));

Reference _rm(double value) => Reference(
  id: 'rm-$value',
  clubId: 'c1',
  athleteId: 'ari',
  exerciseId: 'squat',
  type: ReferenceType.rm,
  value: value,
  date: DateTime.utc(2026, 11, 1),
  origin: ReferenceOrigin.values.first,
  auditoria: _audit,
);

WorkFactor _factor(double value) => WorkFactor(
  id: 'f1',
  clubId: 'c1',
  athleteId: 'ari',
  exerciseId: 'squat',
  value: value,
  date: DateTime.utc(2026, 11, 2),
  auditoria: _audit,
);

SetLoadBasis _basis({
  String? rmExerciseId = 'squat',
  double? pct = 80,
  List<Reference>? references,
  List<WorkFactor> factors = const [],
}) => setLoadBasis(
  rmExerciseId: rmExerciseId,
  pct: pct,
  athleteId: 'ari',
  on: DateTime.utc(2026, 11, 16),
  references: references ?? [_rm(100)],
  factors: factors,
);

ProposedSetLoad _propose(
  SetLoadBasis basis, {
  PlanSet target = const PlanSet(reps: 5, pct: 80),
  int adjustment = Ajuste.neutro,
  double? fixedKg,
  double? barKg,
}) => proposedSetLoad(
  basis: basis,
  target: target,
  adjustment: adjustment,
  athleteFixedKg: fixedKg,
  equipo: Equipo.estandarDe('c1'),
  barKg: barKg,
);

void main() {
  group('setLoadBasis', () {
    test('is by RM only with a reference exercise and a positive percent', () {
      expect(_basis().byRm, isTrue);
      expect(_basis(pct: null).byRm, isFalse);
      expect(_basis(pct: 0).byRm, isFalse);
      expect(_basis(rmExerciseId: null).byRm, isFalse);
    });

    test('without a reference exercise it is neutral and has no RM', () {
      final basis = _basis(rmExerciseId: null);

      expect(basis.reference, isNull);
      expect(basis.workFactor, defaultWorkFactor);
    });
  });

  group('proposedSetLoad', () {
    test('applies RM × factor × percent, like pesoPorPorcentaje', () {
      final load = _propose(_basis(factors: [_factor(90)]));

      expect(
        load.kg,
        pesoPorPorcentaje(
          rm: 100,
          pct: 80,
          equipo: Equipo.estandarDe('c1'),
          workFactor: 90,
        ),
      );
      expect(load.appliedPct, 80);
      expect(load.pcts!.pctReal, 72);
    });

    test('applies the adjustment to the percent', () {
      final load = _propose(_basis(), adjustment: 110);

      expect(load.appliedPct, 88);
      expect(load.kg, greaterThan(_propose(_basis()).kg!));
    });

    test('takes the athlete\'s fixed kilos before the plan\'s', () {
      final basis = _basis(rmExerciseId: null, pct: null);
      const target = PlanSet(reps: 12, kg: 10);

      expect(_propose(basis, target: target, fixedKg: 22).kg, 22);
      expect(_propose(basis, target: target).kg, 10);
    });

    test('is empty, not zero, when the RM is missing', () {
      final load = _propose(_basis(references: const []));

      expect(load.kg, isNull);
      expect(load.pcts, isNull);
    });
  });

  group('proposedDaySets', () {
    final squat = Exercise(
      id: 'squat',
      clubId: clubPlataforma,
      name: 'squat',
      categoryIds: const ['primario'],
      metrics: const [Metric.loadPctRm],
      loadReference: const LoadReference.own(),
      auditoria: _audit,
    );
    const blocks = [
      PlanBlock(
        name: 'Principal',
        prescriptions: [
          Prescription(
            exerciseId: 'squat',
            sets: [PlanSet(reps: 5, pct: 80), PlanSet(reps: 3, pct: 90)],
          ),
          Prescription(exerciseId: 'unknown', sets: [PlanSet(reps: 5, kg: 20)]),
          Prescription(sets: [PlanSet(reps: 5)]),
        ],
      ),
    ];

    List<ProposedSet> propose({
      List<WorkFactor> factors = const [],
      Map<String, int> adjustments = const {},
    }) => proposedDaySets(
      blocks: blocks,
      exercises: {'squat': squat},
      athleteId: 'ari',
      on: DateTime.utc(2026, 11, 16),
      references: [_rm(100)],
      factors: factors,
      fixedKg: const {},
      equipo: Equipo.estandarDe('c1'),
      exerciseAdjustments: adjustments,
    );

    test('one entry per set with an exercise, in plan order', () {
      final sets = propose();

      expect(
        [for (final s in sets) (s.prescriptionIndex, s.setIndex, s.exerciseId)],
        [(0, 0, 'squat'), (0, 1, 'squat'), (1, 0, 'unknown')],
      );
      expect(sets.first.kg, 80);
      expect(sets.last.kg, isNull);
    });

    test('carries the factor only when it is not neutral', () {
      expect(propose().first.workFactor, isNull);
      expect(propose(factors: [_factor(90)]).first.workFactor, 90);
    });

    test('applies the exercise adjustment', () {
      expect(propose(adjustments: {'squat': 110}).first.appliedPct, 88);
    });
  });

  group('dayBlocks', () {
    final plan = PublishedPlan(
      weekModels: const [
        WeekModel(
          id: 'A',
          name: 'A',
          days: [
            PlanDay(
              blocks: [PlanBlock(name: 'x', prescriptions: [])],
            ),
          ],
        ),
      ],
      weekAssignment: const ['A', 'A', 'A', 'A'],
      publishedAt: DateTime.utc(2026, 11, 8),
      publishedBy: 'coach',
    );

    test('is empty outside the week', () {
      expect(dayBlocks(plan, week: 1, day: 1), hasLength(1));
      expect(dayBlocks(plan, week: 1, day: 2), isEmpty);
      expect(dayBlocks(plan, week: 1, day: 0), isEmpty);
    });
  });
}
