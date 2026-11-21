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
  String? athleteId,
}) => proposedSetLoad(
  basis: basis,
  target: target,
  adjustment: adjustment,
  athleteFixedKg: fixedKg,
  equipo: Equipo.estandarDe('c1'),
  barKg: barKg,
  athleteId: athleteId,
);

void main() {
  group('frozen per athlete (E5.16)', () {
    const target = PlanSet(
      reps: 5,
      kg: 50,
      byAthlete: {'ari': AthleteSetLoad(pct: 62.5, kg: 50)},
    );

    test('the athlete with frozen kilos gets them, whatever their RM is now', () {
      final load = _propose(_basis(pct: null, references: [_rm(120)]), target: target, athleteId: 'ari');
      expect(load.kg, 50);
      expect(load.appliedPct, 62.5);
    });

    test('the day adjustment scales the frozen kilos to the nearest loadable', () {
      final load = _propose(_basis(pct: null), target: target, athleteId: 'ari', adjustment: 90);
      expect(load.kg, 45);
      expect(load.appliedPct, closeTo(56.25, 0.01));
    });

    test('another athlete goes by what the coach typed', () {
      final load = _propose(_basis(pct: null), target: target, athleteId: 'andi');
      expect(load.kg, 50);
      expect(load.appliedPct, isNull);
    });

    test('travels as porAtleta and is left out when empty', () {
      expect(PlanSet.fromJson(target.toJson()).byAthlete, target.byAthlete);
      expect(target.toJson()['porAtleta'], {
        'ari': {'pct': 62.5, 'kilos': 50.0},
      });
      expect(const PlanSet(reps: 5).toJson().containsKey('porAtleta'), isFalse);
    });
  });

  group('kilos per athlete in a set in kilos', () {
    const target = PlanSet(
      reps: 10,
      byAthlete: {'ari': AthleteSetLoad(kg: 12.5), 'andi': AthleteSetLoad(kg: 16)},
    );
    final basis = _basis(rmExerciseId: null, pct: null);

    test('each athlete gets their own kilos, as typed', () {
      expect(_propose(basis, target: target, athleteId: 'ari').kg, 12.5);
      expect(_propose(basis, target: target, athleteId: 'andi').kg, 16);
    });

    test('a fixed weight takes no day adjustment and carries no %', () {
      final load = _propose(basis, target: target, athleteId: 'ari', adjustment: 90);
      expect(load.kg, 12.5);
      expect(load.appliedPct, isNull);
      expect(load.pcts, isNull);
    });

    test('they win over the athlete\'s fixed kilos for the exercise', () {
      expect(_propose(basis, target: target, athleteId: 'ari', fixedKg: 20).kg, 12.5);
    });

    test('an athlete added later gets their fixed kilos, else nothing (never another athlete\'s)', () {
      expect(_propose(basis, target: target, athleteId: 'new', fixedKg: 20).kg, 20);
      expect(_propose(basis, target: target, athleteId: 'new').kg, isNull);
    });

    test('a set planned with one weight still gives it to everyone', () {
      expect(_propose(basis, target: const PlanSet(reps: 10, kg: 14), athleteId: 'andi').kg, 14);
    });

    test('travel as porAtleta with kilos only', () {
      expect(target.toJson()['porAtleta'], {
        'ari': {'kilos': 12.5},
        'andi': {'kilos': 16.0},
      });
      expect(PlanSet.fromJson(target.toJson()).byAthlete, target.byAthlete);
    });

    test('plannedKg is the athlete\'s own, else the set\'s one weight', () {
      const mixed = PlanSet(reps: 10, kg: 14, byAthlete: {'ari': AthleteSetLoad(kg: 12.5)});
      expect(plannedKg(mixed, 'ari'), 12.5);
      expect(plannedKg(mixed, 'andi'), 14);
      expect(plannedKg(target, 'new'), isNull);
    });

    test('proposedDaySets gives each athlete theirs', () {
      final curl = Exercise(
        id: 'curl',
        clubId: clubPlataforma,
        name: 'curl',
        categoryIds: const ['accesorio'],
        metrics: const [Metric.fixedLoad, Metric.reps],
        auditoria: _audit,
      );
      List<ProposedSet> day(String athleteId) => proposedDaySets(
        blocks: const [
          PlanBlock(
            name: 'Accesorios',
            prescriptions: [Prescription(exerciseId: 'curl', sets: [target])],
          ),
        ],
        exercises: {'curl': curl},
        athleteId: athleteId,
        on: DateTime.utc(2026, 11, 16),
        references: const [],
        factors: const [],
        fixedKg: const {},
        equipo: Equipo.estandarDe('c1'),
        sessionAdjustment: 95,
      );
      expect(day('ari').single.kg, 12.5);
      expect(day('andi').single.kg, 16);
      expect(day('new').single.kg, isNull);
    });
  });

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
