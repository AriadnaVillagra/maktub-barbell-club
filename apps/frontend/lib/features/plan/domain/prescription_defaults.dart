import 'package:maktub_core/maktub_core.dart';

/// Default sets and rest timer of a prescription when an exercise is added to a block (decision D16).
///
/// Source: `reference/Plan.html`, constants `SERIES` and `TIMER_POR_DEFECTO`, and function `item()`.
/// The reference keys them by slot (`primario`, `secundario`, `accesorio`); in the M1 model a slot is the
/// id of the block's category, and the base catalog keeps those ids (`primario`, `secundario`,
/// `accesorio`). Any other category gets no defaults.
///
/// The reference has two variants of sets (`descarga` and `carga`), but a [Prescription] has a single list
/// of sets, so the `carga` variant is used: it is the reference's default (`let variante = 'carga'`).
///
/// reference/Plan.html:
///   primario:   carga [[8, 65], [5, 72.5], [3, 80], [3, 80]]   timer desc_180
///   secundario: carga [[6, 50], [6, 50], [6, 50], [6, 50]]     timer desc_120
///   accesorio:  carga [[10, ''], [10, ''], [10, '']]           timer desc_90
const _defaults =
    <String, ({List<({int reps, double? pct})> sets, String timerId})>{
      'primario': (
        sets: [
          (reps: 8, pct: 65),
          (reps: 5, pct: 72.5),
          (reps: 3, pct: 80),
          (reps: 3, pct: 80),
        ],
        timerId: 'desc_180',
      ),
      'secundario': (
        sets: [
          (reps: 6, pct: 50),
          (reps: 6, pct: 50),
          (reps: 6, pct: 50),
          (reps: 6, pct: 50),
        ],
        timerId: 'desc_120',
      ),
      'accesorio': (
        sets: [
          (reps: 10, pct: null),
          (reps: 10, pct: null),
          (reps: 10, pct: null),
        ],
        timerId: 'desc_90',
      ),
    };

/// The prescription a block of category [categoryId] gets when [exercise] is added.
///
/// - Sets: the reference's, with `pct` only if the exercise is loaded by % of RM (a fixed-load exercise
///   gets reps alone; the reference's accessory has no `%` either). An exercise that does not measure
///   repetitions gets no sets, since the defaults are reps.
/// - Timer: the reference's rest timer, set as the prescription's `timerId`, only if it is among
///   [activeTimerIds] (the club's active timers); otherwise empty, as the reference does.
/// - A category other than `primario`, `secundario` or `accesorio` gets neither.
Prescription defaultPrescription(
  Exercise exercise, {
  required String? categoryId,
  required Iterable<String> activeTimerIds,
}) {
  final d = _defaults[categoryId];
  if (d == null) return Prescription(exerciseId: exercise.id);
  final hasPct = exercise.metrics.contains(Metric.loadPctRm);
  return Prescription(
    exerciseId: exercise.id,
    sets: exercise.metrics.contains(Metric.reps)
        ? [
            for (final s in d.sets)
              PlanSet(reps: s.reps, pct: hasPct ? s.pct : null),
          ]
        : const [],
    timerId: activeTimerIds.contains(d.timerId) ? d.timerId : null,
  );
}
