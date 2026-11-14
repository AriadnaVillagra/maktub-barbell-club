/// Steps of the guided mode: a block expanded into a flat list of sets.
///
/// Pure rule over values. See "El motor de pasos" and "Cómo se recorre un bloque" in docs/diseno.md,
/// decision D19 in docs/work/M1-mvp/design.md, and `pasosDe` in reference/Guia.html.
library;

import '../modelos/plan.dart';

/// One step of the guided mode: one set of one prescription, done by [athleteIds] at once.
///
/// [prescription] and [set] are zero-based indexes into the block's prescriptions and into the sets of
/// that prescription. With [AthleteMode.turns] a step always has a single athlete.
class GuidedStep {
  const GuidedStep({
    required this.prescription,
    required this.set,
    required this.athleteIds,
  });

  final int prescription;
  final int set;
  final List<String> athleteIds;

  @override
  bool operator ==(Object other) =>
      other is GuidedStep &&
      other.prescription == prescription &&
      other.set == set &&
      _sameList(other.athleteIds, athleteIds);

  @override
  int get hashCode =>
      Object.hash(prescription, set, Object.hashAll(athleteIds));

  @override
  String toString() => 'GuidedStep(p$prescription s$set $athleteIds)';
}

/// One set of one athlete, already done: what the session records, independent of how the steps were
/// grouped when it was done.
class AthleteSet {
  const AthleteSet(this.athleteId, this.prescription, this.set);

  final String athleteId;
  final int prescription;
  final int set;

  @override
  bool operator ==(Object other) =>
      other is AthleteSet &&
      other.athleteId == athleteId &&
      other.prescription == prescription &&
      other.set == set;

  @override
  int get hashCode => Object.hash(athleteId, prescription, set);

  @override
  String toString() => 'AthleteSet($athleteId p$prescription s$set)';
}

/// An athlete who left a prescription of the block: they skip the sets of it they have left.
class LeftPrescription {
  const LeftPrescription(this.athleteId, this.prescription);

  final String athleteId;
  final int prescription;

  @override
  bool operator ==(Object other) =>
      other is LeftPrescription &&
      other.athleteId == athleteId &&
      other.prescription == prescription;

  @override
  int get hashCode => Object.hash(athleteId, prescription);

  @override
  String toString() => 'LeftPrescription($athleteId p$prescription)';
}

/// The full list of steps of a block, in order.
///
/// [setCounts] has one entry per prescription of the block, in order: how many sets each athlete has in
/// it. An athlete missing from an entry (or with 0) does not have that prescription in their day.
/// [athleteIds] are the athletes training, in the order chosen; it sets the order of the turns and of the
/// athletes inside a simultaneous step. Athletes in [setCounts] but not in [athleteIds] are ignored.
///
/// - [ExecutionMode.sequential]: every set of prescription 1, then every set of prescription 2...
/// - [ExecutionMode.circuit]: set 1 of each prescription, then set 2 of each (A1, B1, A2, B2...); a
///   prescription that runs out of sets is skipped in the following rounds.
/// - [AthleteMode.simultaneous]: one step per set, with every athlete who has that set.
/// - [AthleteMode.turns]: one step per athlete who has that set, in the order of [athleteIds].
///
/// A [ExecutionMode.timed] block has no steps: it is done as a whole. Neither does a block without sets.
List<GuidedStep> guidedSteps({
  required ExecutionMode executionMode,
  required AthleteMode athleteMode,
  required List<String> athleteIds,
  required List<Map<String, int>> setCounts,
}) {
  if (executionMode == ExecutionMode.timed) return const [];

  int countOf(int p, String athlete) => setCounts[p][athlete] ?? 0;

  int longest(Iterable<int> prescriptions) {
    var max = 0;
    for (final p in prescriptions) {
      for (final a in athleteIds) {
        final n = countOf(p, a);
        if (n > max) max = n;
      }
    }
    return max;
  }

  // Each group alternates its prescriptions set by set; a sequential block has one group per
  // prescription, a circuit has one group with all of them.
  final all = [for (var p = 0; p < setCounts.length; p++) p];
  final groups = executionMode == ExecutionMode.circuit
      ? [all]
      : [
          for (final p in all) [p],
        ];

  final steps = <GuidedStep>[];
  for (final group in groups) {
    final rounds = longest(group);
    for (var s = 0; s < rounds; s++) {
      for (final p in group) {
        final withSet = [
          for (final a in athleteIds)
            if (s < countOf(p, a)) a,
        ];
        if (withSet.isEmpty) continue;
        if (athleteMode == AthleteMode.turns) {
          for (final a in withSet) {
            steps.add(GuidedStep(prescription: p, set: s, athleteIds: [a]));
          }
        } else {
          steps.add(
            GuidedStep(
              prescription: p,
              set: s,
              athleteIds: List.unmodifiable(withSet),
            ),
          );
        }
      }
    }
  }
  return steps;
}

/// What is left of [steps]: each step without the athletes who already did that set ([done]) or left
/// that prescription ([left]); a step left without athletes disappears.
///
/// Done sets are tracked per athlete, not per step, so switching the athlete mode mid-block is
/// `pendingSteps(guidedSteps(..., athleteMode: newMode), ...)`: what was done stays done and only what
/// is pending is regrouped in the new mode.
List<GuidedStep> pendingSteps(
  List<GuidedStep> steps, {
  Set<AthleteSet> done = const {},
  Set<LeftPrescription> left = const {},
}) => [
  for (final step in steps)
    if (_remaining(step, done, left) case final athletes
        when athletes.isNotEmpty)
      athletes.length == step.athleteIds.length
          ? step
          : GuidedStep(
              prescription: step.prescription,
              set: step.set,
              athleteIds: List.unmodifiable(athletes),
            ),
];

List<String> _remaining(
  GuidedStep step,
  Set<AthleteSet> done,
  Set<LeftPrescription> left,
) => [
  for (final a in step.athleteIds)
    if (!done.contains(AthleteSet(a, step.prescription, step.set)) &&
        !left.contains(LeftPrescription(a, step.prescription)))
      a,
];

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
