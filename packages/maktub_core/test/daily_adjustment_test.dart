import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

void main() {
  group('two-level adjustment', () {
    test('an exercise level replaces the session level', () {
      expect(effectiveAdjustment(session: 90, exercise: 110), 110);
      expect(
        effectiveAdjustment(session: 90, exercise: 100),
        100,
        reason: '100 is a real override',
      );
    });

    test('without exercise level the session level applies; without either it is 100', () {
      expect(effectiveAdjustment(session: 90), 90);
      expect(effectiveAdjustment(), 100);
    });

    test('removing the exercise level inherits the session level again', () {
      expect(
        nextExerciseAdjustment(exercise: 110, session: 90, delta: 0),
        isNull,
      );
      expect(effectiveAdjustment(session: 90, exercise: null), 90);
    });

    test('removing the session level leaves it at 100', () {
      expect(nextSessionAdjustment(90, 0), 100);
    });

    test('a step starts from the level in force', () {
      expect(nextSessionAdjustment(100, -5), 95);
      expect(nextExerciseAdjustment(session: 90, delta: 5), 95);
      expect(
        nextExerciseAdjustment(exercise: 120, session: 90, delta: -5),
        115,
      );
    });

    test('values are clamped to 50-150 and snapped to steps of 5', () {
      expect(snapAdjustment(40), 50);
      expect(snapAdjustment(160), 150);
      expect(snapAdjustment(103), 105);
      expect(snapAdjustment(102), 100);
      expect(nextSessionAdjustment(150, 5), 150);
      expect(nextSessionAdjustment(50, -5), 50);
      expect(effectiveAdjustment(session: 400), 150);
      expect(effectiveAdjustment(session: 90, exercise: 7), 50);
    });
  });

  group('recalculateSet', () {
    final equipo = Equipo.estandar;

    test('an untouched set recalculates weight and applied %', () {
      // 80 % of the plan with a 95 % adjustment is 76 % applied.
      final r = recalculateSet(
        planPct: 80,
        rm: 100,
        adjustment: 95,
        equipo: equipo,
        touched: false,
      );
      expect(r.appliedPct, 76);
      expect(r.weightKg, pesoPorPorcentaje(rm: 100, pct: 76, equipo: equipo));
      expect(
        r.weightKg,
        isNot(pesoPorPorcentaje(rm: 100, pct: 80, equipo: equipo)),
      );
    });

    test('an untouched set also applies the work factor', () {
      final r = recalculateSet(
        planPct: 75,
        rm: 100,
        adjustment: 100,
        equipo: equipo,
        touched: false,
        workFactor: 80,
      );
      expect(r.weightKg, 60);
    });

    test('a touched set keeps its weight when the adjustment moves', () {
      final r = recalculateSet(
        planPct: 80,
        rm: 100,
        adjustment: 120,
        equipo: equipo,
        touched: true,
        currentWeightKg: 77.5,
        currentAppliedPct: 80,
      );
      expect(r.weightKg, 77.5);
      expect(r.appliedPct, 80);
    });

    test('an untouched set without RM has no weight (null, not zero) but keeps the applied %', () {
      final r = recalculateSet(
        planPct: 80,
        rm: null,
        adjustment: 90,
        equipo: equipo,
        touched: false,
      );
      expect(r.weightKg, isNull);
      expect(r.appliedPct, 72);
    });

    test('the adjustment of one athlete does not alter another', () {
      final a = recalculateSet(
        planPct: 80,
        rm: 100,
        adjustment: 90,
        equipo: equipo,
        touched: false,
      );
      final b = recalculateSet(
        planPct: 80,
        rm: 100,
        adjustment: 100,
        equipo: equipo,
        touched: false,
      );
      expect(a.weightKg, isNot(b.weightKg));
      expect(b.weightKg, pesoPorPorcentaje(rm: 100, pct: 80, equipo: equipo));
    });

    test('does not change RM or work factor inputs (pure on values)', () {
      const rm = 100.0;
      recalculateSet(
        planPct: 80,
        rm: rm,
        adjustment: 50,
        equipo: equipo,
        touched: false,
        workFactor: 90,
      );
      expect(rm, 100.0);
    });
  });
}
