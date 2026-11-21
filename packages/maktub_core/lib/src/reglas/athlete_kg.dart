/// Kilos per athlete in a set in kilos (Ari, 2026-11-21): in a plan for several athletes, a set of an exercise loaded
/// with a fixed weight (a dumbbell press, say) carries one weight per athlete and no general one; the reps are the
/// same for all. They go in `PlanSet.byAthlete` as entries with kilos and no %, next to the frozen % and kilos of the
/// sets by % (E5.16). With a single athlete, or before the plan has an assignment, the set keeps its one weight in
/// `PlanSet.kg`, as before.
library;

import '../modelos/asignacion.dart';
import '../modelos/catalogo.dart';
import '../modelos/plan.dart';

/// Whether [exercise] is loaded in kilos and not by % of an RM: its sets are the ones that ask for kilos per athlete.
bool isKgExercise(Exercise exercise) =>
    exercise.metrics.contains(Metric.fixedLoad) && !exercise.metrics.contains(Metric.loadPctRm);

/// Whether a plan for [athleteIds] asks for kilos per athlete in its sets in kilos: when it is for more than one.
bool asksKgPerAthlete(Iterable<String> athleteIds) => athleteIds.toSet().length > 1;

/// The kilos [set] gives [athleteId]: their own when the set has them, else the set's one weight (a set planned with
/// a single weight, or before kilos per athlete existed). Null when it has neither.
double? plannedKg(PlanSet set, String athleteId) => set.byAthlete[athleteId]?.kg ?? set.kg;

/// Who a plan is for, from [assignments] of that plan (E6.7): those in its active assignments now, once each, in the
/// order they joined; without an active one, those of its latest one (newest start date, ties by id), everyone who
/// was in it if it ended. Empty when the plan was never assigned.
List<String> planAthleteIds(Iterable<Assignment> assignments) {
  final active = [
    for (final a in assignments)
      if (a.status == AssignmentStatus.active) a,
  ];
  if (active.isNotEmpty) {
    return [
      ...{for (final a in active) ...a.currentAthleteIds},
    ];
  }
  final latest = [...assignments]
    ..sort((a, b) {
      final byDate = b.startDate.compareTo(a.startDate);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
  if (latest.isEmpty) return const [];
  final last = latest.first;
  return last.status == AssignmentStatus.ended ? last.athleteIds : last.currentAthleteIds;
}
