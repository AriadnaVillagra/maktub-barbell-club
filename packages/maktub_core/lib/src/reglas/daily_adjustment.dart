/// The daily adjustment in two levels (session and exercise) and the recalculation of untouched sets.
///
/// Pure functions over values, per athlete: nothing here reads a plan or session model, and nothing
/// modifies a saved RM or work factor. See "El ajuste del día" in reference/DISENO.md.
library;

import 'equipo.dart';
import 'porcentajes.dart';

/// Clamps [value] to the allowed range and snaps it to the nearest [Ajuste.paso] (ties go up).
int snapAdjustment(int value) {
  final clamped = Ajuste.acotar(value);
  return (clamped / Ajuste.paso).round() * Ajuste.paso;
}

/// The adjustment in force for an exercise: the exercise level if there is one, else the session level.
///
/// A null [exercise] means "inherited". A null [session] is neutral (100). The result is clamped and
/// snapped to the step.
int effectiveAdjustment({int? session, int? exercise}) =>
    snapAdjustment(exercise ?? session ?? Ajuste.neutro);

/// The session level after a step of [delta] percent points from [current]. A [delta] of 0 resets it to
/// 100 (removing the session adjustment).
int nextSessionAdjustment(int current, int delta) =>
    delta == 0 ? Ajuste.neutro : snapAdjustment(current + delta);

/// The exercise level after a step of [delta] percent points. The step starts from the level in force
/// ([exercise] if set, else [session]). A [delta] of 0 removes the exercise level (returns null), so the
/// exercise inherits the session level again.
int? nextExerciseAdjustment({int? exercise, int? session, required int delta}) {
  if (delta == 0) return null;
  return snapAdjustment(
    effectiveAdjustment(session: session, exercise: exercise) + delta,
  );
}

/// The result of recalculating one set: its proposed weight and the percent that was applied.
class SetRecalculation {
  const SetRecalculation({required this.weightKg, required this.appliedPct});

  /// Null when the athlete has no RM (empty, never zero).
  final double? weightKg;
  final double appliedPct;

  @override
  bool operator ==(Object other) =>
      other is SetRecalculation &&
      other.weightKg == weightKg &&
      other.appliedPct == appliedPct;

  @override
  int get hashCode => Object.hash(weightKg, appliedPct);

  @override
  String toString() => 'SetRecalculation($weightKg kg, $appliedPct %)';
}

/// Recalculates one set of the athlete after the adjustment moved.
///
/// - Untouched: the applied % is [planPct] with [adjustment] ([pctEfectivo]) and the weight is the
///   target of [pesoPorPorcentaje] (RM × [workFactor] × applied %, nearest loadable).
/// - Touched (edited by hand): it keeps [currentWeightKg] and [currentAppliedPct] as they are.
///
/// RM and work factor are only read, never changed.
SetRecalculation recalculateSet({
  required double planPct,
  required double? rm,
  required int adjustment,
  required Equipo equipo,
  required bool touched,
  double? currentWeightKg,
  double? currentAppliedPct,
  double workFactor = 100,
}) {
  if (touched) {
    return SetRecalculation(
      weightKg: currentWeightKg,
      appliedPct: currentAppliedPct ?? pctEfectivo(planPct, adjustment),
    );
  }
  final applied = pctEfectivo(planPct, adjustment);
  return SetRecalculation(
    weightKg: pesoPorPorcentaje(
      rm: rm,
      pct: applied,
      equipo: equipo,
      workFactor: workFactor,
    ),
    appliedPct: applied,
  );
}
