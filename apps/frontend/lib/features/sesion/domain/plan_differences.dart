/// What the day did differently from the plan, for the guided mode's summary (E7.21). Pure: the text is made in
/// `presentation/`.
library;

import 'package:maktub_core/maktub_core.dart';

import 'guided_session.dart';

enum PlanDifferenceKind {
  /// A block without sets that was skipped.
  blockSkipped,

  /// The athlete did none of the exercise's sets.
  notDone,

  /// The athlete did some of the exercise's sets: [PlanDifference.done] of [PlanDifference.planned].
  someSets,

  /// A set done with other kilos or reps than the plan proposed.
  changedSet,
}

class PlanDifference {
  const PlanDifference._(
    this.kind, {
    required this.blockName,
    this.athleteId,
    this.prescriptionIndex,
    this.blockIndex,
    this.done = 0,
    this.planned = 0,
    this.setNumber,
    this.kg,
    this.reps,
    this.planKg,
    this.planReps,
  });

  final PlanDifferenceKind kind;
  final String blockName;
  final int? blockIndex;
  final String? athleteId;
  final int? prescriptionIndex;

  /// For [PlanDifferenceKind.someSets].
  final int done;
  final int planned;

  /// For [PlanDifferenceKind.changedSet]: the set (1-based), what was done and what the plan proposed. A null kg
  /// means the exercise has none.
  final int? setNumber;
  final double? kg;
  final int? reps;
  final double? planKg;
  final int? planReps;
}

/// The differences between what [records] hold and the plan, by athlete and exercise, in the day's order. The plan's
/// kilos are the ones the server proposed ([proposed], by athlete), the same ones the guided mode showed.
///
/// A block that was skipped has no sets done, so each of its exercises reads "did not do it"; only a block without sets
/// has a line of its own. A block that was never reached (the day was left) is not compared.
List<PlanDifference> planDifferences({
  required GuidedSession guided,
  required Iterable<SetRecord> records,
  required Map<String, List<ProposedSet>> proposed,
}) {
  final byKey = {
    for (final r in records)
      if (r.done)
        (r.athleteId, r.blockIndex, r.prescriptionIndex, r.setIndex): r,
  };
  final result = <PlanDifference>[];
  for (final run in guided.runs) {
    if (run.status == GuidedBlockStatus.pending ||
        run.status == GuidedBlockStatus.running) {
      continue;
    }
    final b = run.blockIndex;
    final block = guided.day.blocks[b];
    final hasSets = block.prescriptions.any((p) => p.sets.isNotEmpty);
    if (!hasSets) {
      if (run.status == GuidedBlockStatus.skipped) {
        result.add(
          PlanDifference._(
            PlanDifferenceKind.blockSkipped,
            blockName: block.name,
            blockIndex: b,
          ),
        );
      }
      continue;
    }
    for (var p = 0; p < block.prescriptions.length; p++) {
      final sets = block.prescriptions[p].sets;
      if (sets.isEmpty) continue;
      for (final a in guided.athleteIds) {
        PlanDifference make(
          PlanDifferenceKind kind, {
          int done = 0,
          int? set,
          double? kg,
          int? reps,
          double? planKg,
          int? planReps,
        }) => PlanDifference._(
          kind,
          blockName: block.name,
          blockIndex: b,
          athleteId: a,
          prescriptionIndex: p,
          done: done,
          planned: sets.length,
          setNumber: set,
          kg: kg,
          reps: reps,
          planKg: planKg,
          planReps: planReps,
        );

        final did = [
          for (var s = 0; s < sets.length; s++)
            if (byKey[(a, b, p, s)] case final r?) (s, r),
        ];
        if (did.isEmpty) {
          result.add(make(PlanDifferenceKind.notDone));
          continue;
        }
        if (did.length < sets.length) {
          result.add(make(PlanDifferenceKind.someSets, done: did.length));
        }
        for (final (s, r) in did) {
          final proposedKg = (proposed[a] ?? const [])
              .where(
                (x) =>
                    x.blockIndex == b &&
                    x.prescriptionIndex == p &&
                    x.setIndex == s,
              )
              .firstOrNull
              ?.kg;
          final planReps = sets[s].reps;
          final kgDiffers =
              r.kg != null &&
              proposedKg != null &&
              (r.kg! - proposedKg).abs() > 0.001;
          final repsDiffers =
              r.reps != null && planReps != null && r.reps != planReps;
          if (kgDiffers || repsDiffers) {
            result.add(
              make(
                PlanDifferenceKind.changedSet,
                set: s + 1,
                kg: r.kg,
                reps: r.reps,
                planKg: proposedKg ?? r.kg,
                planReps: planReps ?? r.reps,
              ),
            );
          }
        }
      }
    }
  }
  return result;
}
