// Verification of the load rules (E4.1 to E4.5) against the old reference app (E4.6).
//
// The cases live here as plain values so the suite runs without `reference/` or `docs/planillas/`
// (both are git-ignored). Each group says where its expected values come from:
//
// - REFERENCE: the old app's result for the same inputs. The RMs are the February 2026 test ones
//   (sheet RMs). Weights come from running the reference's own `cargable`, `pctEfectivo` and
//   `normalizarPct` (reference/Index.html) on those RMs and on every % written in its plans
//   (PlanEjercicios sheet); the reference's code is not copied. % ramps and the % derived from typed
//   weights are the values the old app stored in the sheets.
// - SPEC: no reference exists (work factor, fixed weight, touched sets); expected values are worked
//   out by hand from the rule stated in the design docs.
//
// RMs are anonymous numbers (no names, no dates).
import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

/// (rm, planPct, dayAdjustment, expectedKg) with the standard equipment.
const _referenceKilos = <(double, double, int, double)>[
  (70, 25.0, 100, 20.0),
  (70, 25.0, 90, 20.0),
  (70, 25.0, 110, 20.0),
  (70, 44.5, 100, 30.5),
  (70, 44.5, 90, 28.0),
  (70, 44.5, 110, 35.0),
  (70, 46.2, 100, 32.5),
  (70, 46.2, 90, 30.0),
  (70, 46.2, 110, 35.5),
  (70, 62.3, 100, 43.0),
  (70, 62.3, 90, 40.0),
  (70, 62.3, 110, 48.0),
  (70, 65.6, 100, 45.5),
  (70, 65.6, 90, 40.5),
  (70, 65.6, 110, 50.5),
  (70, 80.0, 100, 55.5),
  (70, 80.0, 90, 50.5),
  (70, 80.0, 110, 62.5),
  (70, 85.0, 100, 60.0),
  (70, 85.0, 90, 53.0),
  (70, 85.0, 110, 65.5),
  (70, 21.1, 100, 20.0),
  (70, 21.1, 90, 20.0),
  (70, 21.1, 110, 20.0),
  (70, 40.7, 100, 28.0),
  (70, 40.7, 90, 25.5),
  (70, 40.7, 110, 30.5),
  (70, 42.4, 100, 30.0),
  (70, 42.4, 90, 27.5),
  (70, 42.4, 110, 32.5),
  (70, 60.4, 100, 42.5),
  (70, 60.4, 90, 38.0),
  (70, 60.4, 110, 47.5),
  (70, 63.7, 100, 45.0),
  (70, 63.7, 90, 40.0),
  (70, 63.7, 110, 50.0),
  (70, 33.3, 100, 23.0),
  (70, 33.3, 90, 20.0),
  (70, 33.3, 110, 25.5),
  (70, 57.4, 100, 40.0),
  (70, 57.4, 90, 35.5),
  (70, 57.4, 110, 45.0),
  (70, 59.9, 100, 42.5),
  (70, 59.9, 90, 37.5),
  (70, 59.9, 110, 45.5),
  (70, 60.0, 100, 42.5),
  (70, 60.0, 90, 38.0),
  (70, 60.0, 110, 45.5),
  (70, 65.0, 100, 45.5),
  (70, 65.0, 90, 40.5),
  (70, 65.0, 110, 50.0),
  (70, 70.0, 100, 48.0),
  (70, 70.0, 90, 45.0),
  (70, 70.0, 110, 53.0),
  (70, 72.5, 100, 50.5),
  (70, 72.5, 90, 45.5),
  (70, 72.5, 110, 55.5),
  (80, 25.0, 100, 20.0),
  (80, 25.0, 90, 20.0),
  (80, 25.0, 110, 22.5),
  (80, 44.5, 100, 35.5),
  (80, 44.5, 90, 32.5),
  (80, 44.5, 110, 40.0),
  (80, 46.2, 100, 37.5),
  (80, 46.2, 90, 33.0),
  (80, 46.2, 110, 40.5),
  (80, 62.3, 100, 50.0),
  (80, 62.3, 90, 45.0),
  (80, 62.3, 110, 55.0),
  (80, 65.6, 100, 52.5),
  (80, 65.6, 90, 47.5),
  (80, 65.6, 110, 57.5),
  (80, 80.0, 100, 63.0),
  (80, 80.0, 90, 57.5),
  (80, 80.0, 110, 70.5),
  (80, 85.0, 100, 68.0),
  (80, 85.0, 90, 60.5),
  (80, 85.0, 110, 75.0),
  (80, 21.1, 100, 20.0),
  (80, 21.1, 90, 20.0),
  (80, 21.1, 110, 20.0),
  (80, 40.7, 100, 32.5),
  (80, 40.7, 90, 30.0),
  (80, 40.7, 110, 35.5),
  (80, 42.4, 100, 33.0),
  (80, 42.4, 90, 30.5),
  (80, 42.4, 110, 37.5),
  (80, 60.4, 100, 48.0),
  (80, 60.4, 90, 43.0),
  (80, 60.4, 110, 53.0),
  (80, 63.7, 100, 50.5),
  (80, 63.7, 90, 45.5),
  (80, 63.7, 110, 55.5),
  (80, 33.3, 100, 27.5),
  (80, 33.3, 90, 23.0),
  (80, 33.3, 110, 30.0),
  (80, 57.4, 100, 45.5),
  (80, 57.4, 90, 40.5),
  (80, 57.4, 110, 50.5),
  (80, 59.9, 100, 48.0),
  (80, 59.9, 90, 43.0),
  (80, 59.9, 110, 52.5),
  (80, 60.0, 100, 48.0),
  (80, 60.0, 90, 43.0),
  (80, 60.0, 110, 53.0),
  (80, 65.0, 100, 52.5),
  (80, 65.0, 90, 47.5),
  (80, 65.0, 110, 57.5),
  (80, 70.0, 100, 55.5),
  (80, 70.0, 90, 50.5),
  (80, 70.0, 110, 62.5),
  (80, 72.5, 100, 58.0),
  (80, 72.5, 90, 52.5),
  (80, 72.5, 110, 63.0),
  (95, 25.0, 100, 23.0),
  (95, 25.0, 90, 22.5),
  (95, 25.0, 110, 25.5),
  (95, 44.5, 100, 42.5),
  (95, 44.5, 90, 38.0),
  (95, 44.5, 110, 47.5),
  (95, 46.2, 100, 43.0),
  (95, 46.2, 90, 40.0),
  (95, 46.2, 110, 48.0),
  (95, 62.3, 100, 60.0),
  (95, 62.3, 90, 53.0),
  (95, 62.3, 110, 65.0),
  (95, 65.6, 100, 62.5),
  (95, 65.6, 90, 55.5),
  (95, 65.6, 110, 68.0),
  (95, 80.0, 100, 75.5),
  (95, 80.0, 90, 68.0),
  (95, 80.0, 110, 83.0),
  (95, 85.0, 100, 80.5),
  (95, 85.0, 90, 72.5),
  (95, 85.0, 110, 88.0),
  (95, 21.1, 100, 20.0),
  (95, 21.1, 90, 20.0),
  (95, 21.1, 110, 22.5),
  (95, 40.7, 100, 38.0),
  (95, 40.7, 90, 35.0),
  (95, 40.7, 110, 42.5),
  (95, 42.4, 100, 40.5),
  (95, 42.4, 90, 35.5),
  (95, 42.4, 110, 45.0),
  (95, 60.4, 100, 57.5),
  (95, 60.4, 90, 52.5),
  (95, 60.4, 110, 63.0),
  (95, 63.7, 100, 60.5),
  (95, 63.7, 90, 55.0),
  (95, 63.7, 110, 67.5),
  (95, 33.3, 100, 32.5),
  (95, 33.3, 90, 28.0),
  (95, 33.3, 110, 35.0),
  (95, 57.4, 100, 55.0),
  (95, 57.4, 90, 50.0),
  (95, 57.4, 110, 60.0),
  (95, 59.9, 100, 57.5),
  (95, 59.9, 90, 50.5),
  (95, 59.9, 110, 62.5),
  (95, 60.0, 100, 57.5),
  (95, 60.0, 90, 50.5),
  (95, 60.0, 110, 62.5),
  (95, 65.0, 100, 62.5),
  (95, 65.0, 90, 55.5),
  (95, 65.0, 110, 68.0),
  (95, 70.0, 100, 65.5),
  (95, 70.0, 90, 60.0),
  (95, 70.0, 110, 73.0),
  (95, 72.5, 100, 68.0),
  (95, 72.5, 90, 62.5),
  (95, 72.5, 110, 75.5),
  (55, 25.0, 100, 20.0),
  (55, 25.0, 90, 20.0),
  (55, 25.0, 110, 20.0),
  (55, 44.5, 100, 25.0),
  (55, 44.5, 90, 22.5),
  (55, 44.5, 110, 27.5),
  (55, 46.2, 100, 25.5),
  (55, 46.2, 90, 23.0),
  (55, 46.2, 110, 28.0),
  (55, 62.3, 100, 35.0),
  (55, 62.3, 90, 30.5),
  (55, 62.3, 110, 37.5),
  (55, 65.6, 100, 35.5),
  (55, 65.6, 90, 32.5),
  (55, 65.6, 110, 40.0),
  (55, 80.0, 100, 43.0),
  (55, 80.0, 90, 40.0),
  (55, 80.0, 110, 48.0),
  (55, 85.0, 100, 47.5),
  (55, 85.0, 90, 42.5),
  (55, 85.0, 110, 50.5),
  (55, 21.1, 100, 20.0),
  (55, 21.1, 90, 20.0),
  (55, 21.1, 110, 20.0),
  (55, 40.7, 100, 22.5),
  (55, 40.7, 90, 20.0),
  (55, 40.7, 110, 25.0),
  (55, 42.4, 100, 23.0),
  (55, 42.4, 90, 20.0),
  (55, 42.4, 110, 25.5),
  (55, 60.4, 100, 33.0),
  (55, 60.4, 90, 30.0),
  (55, 60.4, 110, 37.5),
  (55, 63.7, 100, 35.0),
  (55, 63.7, 90, 32.5),
  (55, 63.7, 110, 38.0),
  (55, 33.3, 100, 20.0),
  (55, 33.3, 90, 20.0),
  (55, 33.3, 110, 20.0),
  (55, 57.4, 100, 32.5),
  (55, 57.4, 90, 28.0),
  (55, 57.4, 110, 35.0),
  (55, 59.9, 100, 33.0),
  (55, 59.9, 90, 30.0),
  (55, 59.9, 110, 35.5),
  (55, 60.0, 100, 33.0),
  (55, 60.0, 90, 30.0),
  (55, 60.0, 110, 35.5),
  (55, 65.0, 100, 35.5),
  (55, 65.0, 90, 32.5),
  (55, 65.0, 110, 40.0),
  (55, 70.0, 100, 38.0),
  (55, 70.0, 90, 35.0),
  (55, 70.0, 110, 42.5),
  (55, 72.5, 100, 40.0),
  (55, 72.5, 90, 35.5),
  (55, 72.5, 110, 43.0),
  (60, 25.0, 100, 20.0),
  (60, 25.0, 90, 20.0),
  (60, 25.0, 110, 20.0),
  (60, 44.5, 100, 27.5),
  (60, 44.5, 90, 25.0),
  (60, 44.5, 110, 30.0),
  (60, 46.2, 100, 27.5),
  (60, 46.2, 90, 25.0),
  (60, 46.2, 110, 30.5),
  (60, 62.3, 100, 37.5),
  (60, 62.3, 90, 33.0),
  (60, 62.3, 110, 40.5),
  (60, 65.6, 100, 40.0),
  (60, 65.6, 90, 35.5),
  (60, 65.6, 110, 43.0),
  (60, 80.0, 100, 48.0),
  (60, 80.0, 90, 43.0),
  (60, 80.0, 110, 53.0),
  (60, 85.0, 100, 50.5),
  (60, 85.0, 90, 45.5),
  (60, 85.0, 110, 55.5),
  (60, 21.1, 100, 20.0),
  (60, 21.1, 90, 20.0),
  (60, 21.1, 110, 20.0),
  (60, 40.7, 100, 25.0),
  (60, 40.7, 90, 22.5),
  (60, 40.7, 110, 27.5),
  (60, 42.4, 100, 25.5),
  (60, 42.4, 90, 23.0),
  (60, 42.4, 110, 28.0),
  (60, 60.4, 100, 35.5),
  (60, 60.4, 90, 32.5),
  (60, 60.4, 110, 40.0),
  (60, 63.7, 100, 38.0),
  (60, 63.7, 90, 35.0),
  (60, 63.7, 110, 42.5),
  (60, 33.3, 100, 20.0),
  (60, 33.3, 90, 20.0),
  (60, 33.3, 110, 22.5),
  (60, 57.4, 100, 35.0),
  (60, 57.4, 90, 30.5),
  (60, 57.4, 110, 38.0),
  (60, 59.9, 100, 35.5),
  (60, 59.9, 90, 32.5),
  (60, 59.9, 110, 40.0),
  (60, 60.0, 100, 35.5),
  (60, 60.0, 90, 32.5),
  (60, 60.0, 110, 40.0),
  (60, 65.0, 100, 38.0),
  (60, 65.0, 90, 35.0),
  (60, 65.0, 110, 43.0),
  (60, 70.0, 100, 42.5),
  (60, 70.0, 90, 38.0),
  (60, 70.0, 110, 45.5),
  (60, 72.5, 100, 43.0),
  (60, 72.5, 90, 40.0),
  (60, 72.5, 110, 48.0),
];

/// Ramps stored by the old importer in the plan sheet: group sizes, work %, the RMs of the two
/// athletes of the group, and the % of every set the sheet holds.
class _Ramp {
  const _Ramp(this.name, this.groups, this.workPct, this.rms, this.expected);
  final String name;
  final List<int> groups;
  final double workPct;
  final List<double> rms;
  final List<double> expected;
}

const _referenceRamps = <_Ramp>[
  _Ramp('squat unload', [1, 1, 1, 3], 80, [70, 80], [
    25,
    44.5,
    62.3,
    80,
    80,
    80,
  ]),
  _Ramp('squat load', [1, 1, 1, 4], 85, [70, 80], [
    25,
    46.2,
    65.6,
    85,
    85,
    85,
    85,
  ]),
  _Ramp('deadlift unload', [1, 1, 1, 3], 80, [95, 95], [
    21.1,
    40.7,
    60.4,
    80,
    80,
    80,
  ]),
  _Ramp('deadlift load', [1, 1, 1, 4], 85, [95, 95], [
    21.1,
    42.4,
    63.7,
    85,
    85,
    85,
    85,
  ]),
  _Ramp('deadlift load 2', [1, 1, 1, 4], 80, [95, 95], [
    21.1,
    40.7,
    60.4,
    80,
    80,
    80,
    80,
  ]),
  _Ramp('bench unload', [1, 1, 3], 80, [55, 60], [33.3, 57.4, 80, 80, 80]),
  _Ramp('bench load', [1, 1, 4], 85, [55, 60], [33.3, 59.9, 85, 85, 85, 85]),
];

/// Hand-typed weights the old app saved with the % it derived: (rm, kg, savedPct).
const _referenceDerivedPcts = <(double, double, double)>[
  (70, 17.5, 25),
  (70, 30, 42.86),
  (70, 42.5, 60.71),
  (70, 55, 78.57),
  (80, 20, 25),
  (80, 35, 43.75),
  (80, 50, 62.5),
  (80, 65, 81.25),
];

void main() {
  final equipo = Equipo.estandar;

  group('REFERENCE: weight = nearest loadable of rm x adjusted %', () {
    test('has the expected number of cases', () {
      expect(_referenceKilos.length, 285);
    });

    for (final (rm, planPct, adjustment, kg) in _referenceKilos) {
      test('rm $rm, plan $planPct %, adjustment $adjustment % -> $kg kg', () {
        final applied = pctEfectivo(planPct, adjustment);
        expect(pesoPorPorcentaje(rm: rm, pct: applied, equipo: equipo), kg);
        // The same result through the set recalculation (untouched set).
        final set = recalculateSet(
          planPct: planPct,
          rm: rm,
          adjustment: adjustment,
          equipo: equipo,
          touched: false,
        );
        expect(set.weightKg, kg);
        expect(set.appliedPct, applied);
      });
    }

    test('80 % of an 80 kg RM is 63 kg, the nearest loadable that wins the tie downwards', () {
      // reference/DISENO.md: the 63 kg written in the sheet is the nearest loadable to 64 kg.
      expect(pesoPorPorcentaje(rm: 80, pct: 80, equipo: equipo), 63);
    });
  });

  group('REFERENCE: ramp percentages stored in the plan sheet', () {
    for (final r in _referenceRamps) {
      test(r.name, () {
        expect(
          rampPercentages(
            groupSizes: r.groups,
            workPct: r.workPct,
            athletes: [for (final rm in r.rms) RampAthlete(rm: rm)],
            equipo: equipo,
          ),
          r.expected,
        );
      });
    }

    test(
      'the empty bar never gets extra plates for the lighter-RM athlete',
      () {
        // 20 kg over each RM: nobody is proposed more than the empty bar on the first set.
        for (final rm in [70.0, 80.0]) {
          final pct = rampPercentages(
            groupSizes: [1, 1, 1, 3],
            workPct: 80,
            athletes: const [RampAthlete(rm: 70), RampAthlete(rm: 80)],
            equipo: equipo,
          ).first;
          expect(pesoPorPorcentaje(rm: rm, pct: pct, equipo: equipo), 20);
        }
      },
    );
  });

  group('REFERENCE: % derived from typed weights', () {
    for (final (rm, kg, saved) in _referenceDerivedPcts) {
      test('rm $rm, $kg kg -> $saved %', () {
        expect(pctDesdePeso(kg, rm), saved);
      });
    }

    test('going back through the weight gives the typed weight or the nearest loadable', () {
      for (final (rm, kg, _) in _referenceDerivedPcts) {
        final pct = pctDesdePeso(kg, rm)!;
        expect(
          pesoPorPorcentaje(rm: rm, pct: pct, equipo: equipo),
          equipo.masCercano(kg),
        );
      }
    });
  });

  group('REFERENCE: fixed weight and missing data', () {
    test('an exercise without reference takes the fixed weight as loaded', () {
      final p = proposeLoad(
        hasReference: false,
        pct: 60,
        rm: 70,
        fixedKg: 18,
        equipo: equipo,
      );
      expect(p, const LoadProposal(source: LoadSource.fixed, weightKg: 18));
    });

    test('a % with a reference and no RM proposes nothing (it does not use the fixed weight)', () {
      final p = proposeLoad(
        hasReference: true,
        pct: 80,
        rm: null,
        fixedKg: 18,
        equipo: equipo,
      );
      expect(p, const LoadProposal(source: LoadSource.rm, weightKg: null));
    });
  });

  group('SPEC: work factor (no reference)', () {
    // Weights are the reference's results for the RM already multiplied by the factor, so a factor
    // is exactly "a lower RM": 70 x 80 % = 56 and 80 x 93 % = 74.4.
    test('rm 70, factor 80 %, 80 % -> 45 kg (reference with rm 56)', () {
      expect(
        pesoPorPorcentaje(rm: 70, pct: 80, equipo: equipo, workFactor: 80),
        45,
      );
    });

    test('rm 70, factor 80 %, 62.3 % -> 35 kg (reference with rm 56)', () {
      expect(
        pesoPorPorcentaje(rm: 70, pct: 62.3, equipo: equipo, workFactor: 80),
        35,
      );
    });

    test('rm 70, factor 80 %, 85 % -> 47.5 kg (reference with rm 56)', () {
      expect(
        pesoPorPorcentaje(rm: 70, pct: 85, equipo: equipo, workFactor: 80),
        47.5,
      );
    });

    test('rm 80, factor 93 %, 80 % -> 60 kg (reference with rm 74.4)', () {
      expect(
        pesoPorPorcentaje(rm: 80, pct: 80, equipo: equipo, workFactor: 93),
        60,
      );
    });

    test('factor 100 % is the same as no factor', () {
      expect(
        pesoPorPorcentaje(rm: 70, pct: 80, equipo: equipo, workFactor: 100),
        pesoPorPorcentaje(rm: 70, pct: 80, equipo: equipo),
      );
    });

    test('the day adjustment applies on top of the factor: rm 70, 80 %, 90 % adjust -> 40.5 kg', () {
      final set = recalculateSet(
        planPct: 80,
        rm: 70,
        adjustment: 90,
        equipo: equipo,
        touched: false,
        workFactor: 80,
      );
      expect(set.weightKg, 40.5);
    });

    test('proposeLoad carries the factor', () {
      final p = proposeLoad(
        hasReference: true,
        pct: 80,
        rm: 70,
        fixedKg: null,
        equipo: equipo,
        workFactor: 80,
      );
      expect(p, const LoadProposal(source: LoadSource.rm, weightKg: 45));
    });

    test(
      'a typed weight gives the % over rm x factor, and back to the weight',
      () {
        // 45 kg over 70 x 80 % = 56 kg is 80.36 %; the weight comes back from that %.
        final pct = pctDesdePeso(45, 70, workFactor: 80);
        expect(pct, 80.36);
        expect(
          pesoPorPorcentaje(rm: 70, pct: pct!, equipo: equipo, workFactor: 80),
          45,
        );
      },
    );

    test('ramp with factor: the empty bar over rm x factor', () {
      // rm 70 x 80 % = 56 kg base: 20 / 56 = 35.7 %, and the work block keeps 80 %.
      final pcts = rampPercentages(
        groupSizes: [1, 3],
        workPct: 80,
        athletes: const [RampAthlete(rm: 70, workFactor: 80)],
        equipo: equipo,
      );
      expect(pcts, [35.7, 80, 80, 80]);
      expect(
        pesoPorPorcentaje(
          rm: 70,
          pct: pcts.first,
          equipo: equipo,
          workFactor: 80,
        ),
        20,
      );
    });
  });

  group('SPEC: touched sets and the two adjustment levels', () {
    test(
      'a touched set keeps its weight and applied % when the adjustment moves',
      () {
        final set = recalculateSet(
          planPct: 80,
          rm: 80,
          adjustment: 90,
          equipo: equipo,
          touched: true,
          currentWeightKg: 65,
          currentAppliedPct: 81.25,
        );
        expect(set.weightKg, 65);
        expect(set.appliedPct, 81.25);
      },
    );

    test('an exercise level overrides the session level; clearing it inherits again', () {
      expect(effectiveAdjustment(session: 90, exercise: 110), 110);
      expect(effectiveAdjustment(session: 90), 90);
      expect(
        nextExerciseAdjustment(exercise: 110, session: 90, delta: 0),
        isNull,
      );
    });

    test('the daily adjustment never changes the RM: same rm, back to 100 % gives the same weight', () {
      int adjustment = 100;
      adjustment = nextSessionAdjustment(adjustment, -10);
      adjustment = nextSessionAdjustment(adjustment, 0);
      final set = recalculateSet(
        planPct: 80,
        rm: 80,
        adjustment: adjustment,
        equipo: equipo,
        touched: false,
      );
      expect(set.weightKg, 63);
    });
  });
}
