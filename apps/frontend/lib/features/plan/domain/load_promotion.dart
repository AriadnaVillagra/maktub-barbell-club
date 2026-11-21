import 'package:maktub_core/maktub_core.dart';

/// Whether [exercise] is "con peso": it measures a load, by % of RM or fixed.
bool isWeighted(Exercise exercise) => exercise.metrics.any((m) => m.isLoad);

/// [exercise] made weighted because a plan gives it a weight in [sets] (Ari, 2026-11-21): a % adds "Carga (% del
/// RM)", kilos alone (the set's, or each athlete's) add "Carga fija". Loaded by %, an exercise without a reference gets its own RM when it measures
/// reps, so its % works out kilos from each athlete's RM like any other. Null when it is already weighted or no set
/// has a weight.
Exercise? weightedBySets(Exercise exercise, Iterable<PlanSet> sets) {
  if (isWeighted(exercise)) return null;
  final byPct = sets.any((s) => (s.pct ?? 0) > 0);
  // Kilos per athlete in a plan for several athletes have no %.
  final byKg = sets.any(
    (s) => (s.kg ?? 0) > 0 || s.byAthlete.values.any((l) => l.pct == null && (l.kg ?? 0) > 0),
  );
  if (!byPct && !byKg) return null;
  final weighted = exercise.copyWith(
    metrics: [byPct ? Metric.loadPctRm : Metric.fixedLoad, ...exercise.metrics],
  );
  return byPct && exercise.loadReference.kind == LoadReferenceKind.none && weighted.measuresLoadTimesReps
      ? weighted.copyWith(loadReference: const LoadReference.own())
      : weighted;
}

/// The exercises of [plan] that are not weighted but got a weight, made weighted ([weightedBySets]), by id. Only
/// those [canWrite] allows: the others stay as they are.
Map<String, Exercise> exercisesGainingLoad(
  Plan plan,
  Map<String, Exercise> exercises, {
  required bool Function(Exercise) canWrite,
}) {
  final sets = <String, List<PlanSet>>{};
  for (final model in plan.weekModels) {
    for (final day in model.days) {
      for (final block in day.blocks) {
        for (final p in block.prescriptions) {
          if (p.exerciseId case final id?) (sets[id] ??= []).addAll(p.sets);
        }
      }
    }
  }
  return {
    for (final MapEntry(key: id, value: list) in sets.entries)
      if (exercises[id] case final exercise? when canWrite(exercise))
        id: ?weightedBySets(exercise, list),
  };
}
