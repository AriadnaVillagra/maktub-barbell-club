/// The load of one set for one athlete on the session's date: what proposing a weight and recording it share,
/// so a proposed value and the value later recorded agree. Pure; the caller reads the data.
library;

import '../modelos/catalogo.dart';
import '../modelos/plan.dart';
import '../modelos/referencias.dart';
import '../modelos/sesion.dart';
import 'catalogo.dart';
import 'daily_adjustment.dart';
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

/// Proposes the weight of [target] on [basis]: the kilos frozen for [athleteId] in the plan (E5.16) with
/// [adjustment], else RM × work factor × % with [adjustment] when it is measured by RM, otherwise [athleteFixedKg]
/// and then the plan's own kilos. Rounded on [barKg] (the prescription's bar, else the exercise's; null is the
/// default bar).
ProposedSetLoad proposedSetLoad({
  required SetLoadBasis basis,
  required PlanSet target,
  required int adjustment,
  required double? athleteFixedKg,
  required Equipo equipo,
  double? barKg,
  String? athleteId,
}) {
  if (target.byAthlete[athleteId]?.kg case final frozen? when frozen > 0) {
    final own = target.byAthlete[athleteId]!.pct;
    final applied = own == null ? null : pctEfectivo(own, adjustment);
    return ProposedSetLoad(
      kg: adjustment == 100 ? frozen : equipo.cargableOExacto(frozen * adjustment / 100, barKg: barKg),
      appliedPct: applied,
      pcts: applied != null && basis.rmExerciseId != null
          ? RecordPcts.fromPlan(applied, workFactor: basis.workFactor)
          : null,
    );
  }
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

/// The blocks of the 1-based [day] of the 1-based [week] in [plan]; empty if that week has no model or that day.
List<PlanBlock> dayBlocks(
  PublishedPlan plan, {
  required int week,
  required int day,
}) {
  final days = plan.weekModelOf(week)?.days ?? const <PlanDay>[];
  return day >= 1 && day <= days.length
      ? days[day - 1].blocks
      : const <PlanBlock>[];
}

/// The exercises that [blocks] prescribe and [exercises] knows, by id, each with the id of the exercise whose RM
/// loads it ([rmExerciseIdFor]). Tells the caller which references, factors and fixed weights to read.
Map<String, String?> rmExerciseIdsOf(
  List<PlanBlock> blocks,
  Map<String, Exercise> exercises,
) => {
  for (final block in blocks)
    for (final p in block.prescriptions)
      if (exercises[p.exerciseId] case final exercise?)
        exercise.id: rmExerciseIdFor(exercise, exercises),
};

/// The proposed kilos of every set of [blocks] for [athleteId] on [on], in plan order: RM × work factor × % with
/// the day's adjustment ([effectiveAdjustment] of [sessionAdjustment] and [exerciseAdjustments]), else the
/// athlete's fixed kilos ([fixedKg], by exercise id) and then the plan's, rounded on the prescription's bar or
/// else the exercise's. A set of an exercise [exercises] doesn't know carries no kilos. [workFactor] is set only
/// when the weight came from the RM and the factor is not neutral; hiding it from the viewer is the caller's job.
List<ProposedSet> proposedDaySets({
  required List<PlanBlock> blocks,
  required Map<String, Exercise> exercises,
  required String athleteId,
  required DateTime on,
  required Iterable<Reference> references,
  required Iterable<WorkFactor> factors,
  required Map<String, double> fixedKg,
  required Equipo equipo,
  int? sessionAdjustment,
  Map<String, int> exerciseAdjustments = const {},
}) => [
  for (var b = 0; b < blocks.length; b++)
    for (var p = 0; p < blocks[b].prescriptions.length; p++)
      if (blocks[b].prescriptions[p]
          case Prescription(exerciseId: final exerciseId?) &&
              final prescription)
        for (var s = 0; s < prescription.sets.length; s++)
          _proposedSet(
            position: (block: b, prescription: p, set: s),
            exerciseId: exerciseId,
            exercise: exercises[exerciseId],
            prescription: prescription,
            exercises: exercises,
            athleteId: athleteId,
            on: on,
            references: references,
            factors: factors,
            fixedKg: fixedKg[exerciseId],
            equipo: equipo,
            adjustment: effectiveAdjustment(
              session: sessionAdjustment,
              exercise: exerciseAdjustments[exerciseId],
            ),
          ),
];

ProposedSet _proposedSet({
  required ({int block, int prescription, int set}) position,
  required String exerciseId,
  required Exercise? exercise,
  required Prescription prescription,
  required Map<String, Exercise> exercises,
  required String athleteId,
  required DateTime on,
  required Iterable<Reference> references,
  required Iterable<WorkFactor> factors,
  required double? fixedKg,
  required Equipo equipo,
  required int adjustment,
}) {
  if (exercise == null) {
    return ProposedSet(
      blockIndex: position.block,
      prescriptionIndex: position.prescription,
      setIndex: position.set,
      exerciseId: exerciseId,
    );
  }
  final target = prescription.sets[position.set];
  final basis = setLoadBasis(
    rmExerciseId: rmExerciseIdFor(exercise, exercises),
    pct: target.pct ?? target.byAthlete[athleteId]?.pct,
    athleteId: athleteId,
    on: on,
    references: references,
    factors: factors,
  );
  final load = proposedSetLoad(
    basis: basis,
    target: target,
    adjustment: adjustment,
    athleteFixedKg: fixedKg,
    equipo: equipo,
    barKg: prescription.barKg ?? exercise.barKg,
    athleteId: athleteId,
  );
  return ProposedSet(
    blockIndex: position.block,
    prescriptionIndex: position.prescription,
    setIndex: position.set,
    exerciseId: exerciseId,
    kg: load.kg,
    appliedPct: load.appliedPct,
    workFactor: load.pcts != null && basis.workFactor != defaultWorkFactor
        ? basis.workFactor
        : null,
  );
}
