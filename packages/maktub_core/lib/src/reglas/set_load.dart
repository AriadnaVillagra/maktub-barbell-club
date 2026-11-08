/// The load of one set for one athlete on the session's date: what proposing a weight and recording it share,
/// so a proposed value and the value later recorded agree. Pure; the caller reads the data.
library;

import '../modelos/catalogo.dart';
import '../modelos/plan.dart';
import '../modelos/referencias.dart';
import '../modelos/sesion.dart';
import 'catalogo.dart';
import 'equipo.dart';
import 'load_source.dart';
import 'porcentajes.dart';
import 'vigencia.dart';

/// Id of the exercise whose RM loads [exercise] (the end of its reference chain), or null when it is not
/// measured by an RM or its chain has a cycle.
String? rmExerciseIdFor(Exercise exercise, Map<String, Exercise> exercises) =>
    exercise.loadReference.kind == LoadReferenceKind.none
    ? null
    : effectiveRmExerciseId(exercise.id, exercises);

/// What a set's load is measured against for one athlete on one date.
class SetLoadBasis {
  const SetLoadBasis({
    required this.rmExerciseId,
    required this.pct,
    required this.reference,
    required this.workFactor,
  });

  /// See [rmExerciseIdFor].
  final String? rmExerciseId;

  /// The set's % of the plan, before the day's adjustment.
  final double? pct;

  /// The RM in force, or null if the athlete has none.
  final Reference? reference;

  /// The work factor in force (a percent, 100 is neutral).
  final double workFactor;

  /// Whether the weight comes from the RM (a reference exercise and a positive %).
  bool get byRm {
    final value = pct;
    return rmExerciseId != null && value != null && value > 0;
  }
}

/// Resolves the RM and work factor in force on [on]. [references] and [factors] may hold other exercises'.
SetLoadBasis setLoadBasis({
  required String? rmExerciseId,
  required double? pct,
  required String athleteId,
  required DateTime on,
  required Iterable<Reference> references,
  required Iterable<WorkFactor> factors,
}) {
  if (rmExerciseId == null) {
    return SetLoadBasis(
      rmExerciseId: null,
      pct: pct,
      reference: null,
      workFactor: defaultWorkFactor,
    );
  }
  return SetLoadBasis(
    rmExerciseId: rmExerciseId,
    pct: pct,
    reference: currentReference(
      references,
      athleteId: athleteId,
      exerciseId: rmExerciseId,
      type: ReferenceType.rm,
      on: on,
    ),
    workFactor: currentWorkFactor(
      factors,
      references,
      athleteId: athleteId,
      exerciseId: rmExerciseId,
      on: on,
    ),
  );
}

/// The weight proposed for one set, with what it was derived from.
class ProposedSetLoad {
  const ProposedSetLoad({
    required this.kg,
    required this.appliedPct,
    required this.pcts,
  });

  /// Null when there is nothing to propose (no RM, no fixed weight): empty, never zero.
  final double? kg;

  /// The plan's % with the day's adjustment, or null if the set has no %.
  final double? appliedPct;

  /// Both percents; null unless the weight came from the RM.
  final RecordPcts? pcts;
}

/// Proposes the weight of [target] on [basis]: RM × work factor × % with [adjustment] when it is measured by RM,
/// otherwise [athleteFixedKg] and then the plan's own kilos. Rounded on [barKg] (the prescription's bar, else the
/// exercise's; null is the default bar).
ProposedSetLoad proposedSetLoad({
  required SetLoadBasis basis,
  required PlanSet target,
  required int adjustment,
  required double? athleteFixedKg,
  required Equipo equipo,
  double? barKg,
}) {
  final pct = target.pct;
  final applied = pct == null ? null : pctEfectivo(pct, adjustment);
  final kg = proposeLoad(
    hasReference: basis.rmExerciseId != null,
    pct: applied,
    rm: basis.reference?.value,
    fixedKg: athleteFixedKg ?? target.kg,
    equipo: equipo,
    workFactor: basis.workFactor,
    barKg: barKg,
  ).weightKg;
  return ProposedSetLoad(
    kg: kg,
    appliedPct: applied,
    pcts: basis.byRm && kg != null
        ? RecordPcts.fromPlan(applied!, workFactor: basis.workFactor)
        : null,
  );
}
