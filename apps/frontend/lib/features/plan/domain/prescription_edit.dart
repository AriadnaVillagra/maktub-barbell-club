import 'package:maktub_core/maktub_core.dart';

/// Pure operations behind the prescription editor (E5.8). Nothing here validates: reps and `%` out of
/// range are reported when saving (E5.9), so typing is never blocked.

/// A number typed by the coach (comma or point as the decimal separator). Null if empty or not a number.
///
/// Same behaviour as `parsePositive` of the athletes feature, but it keeps zero and negatives so that
/// `validatePlan` can report them when saving; it is duplicated here to avoid a dependency between
/// features.
double? parseTypedNumber(String text) {
  final v = double.tryParse(text.trim().replaceAll(',', '.'));
  return v != null && v.isFinite ? v : null;
}

/// Whole repetitions typed by the coach. Null if empty or not a whole number.
int? parseTypedReps(String text) => int.tryParse(text.trim());

/// [set] with the three fields M1 edits replaced (null clears one); every other field is kept.
PlanSet setWith(
  PlanSet set, {
  required int? reps,
  required double? pct,
  required double? kg,
  Map<String, AthleteSetLoad>? byAthlete,
}) => PlanSet(
  reps: reps,
  maxReps: set.maxReps,
  pct: pct,
  kg: kg,
  seconds: set.seconds,
  distanceM: set.distanceM,
  pctOfMark: set.pctOfMark,
  paceSecPerKm: set.paceSecPerKm,
  pacePct: set.pacePct,
  zone: set.zone,
  calories: set.calories,
  attempt: set.attempt,
  byAthlete: byAthlete ?? set.byAthlete,
);

/// [sets] plus a copy of the last one (the reference does the same). An empty list gets an empty set.
List<PlanSet> addSet(List<PlanSet> sets) => [
  ...sets,
  sets.isEmpty ? const PlanSet() : sets.last,
];

/// [sets] without the one at [index]; a prescription keeps at least one set, so a single set stays.
List<PlanSet> removeSet(List<PlanSet> sets, int index) =>
    sets.length <= 1 || index < 0 || index >= sets.length
    ? sets
    : [
        for (final (i, s) in sets.indexed)
          if (i != index) s,
      ];

/// [p] with sets, note, timer and bar replaced (null clears the last three); the exercise is kept. A blank
/// note is stored as null.
Prescription prescriptionWith(
  Prescription p, {
  required List<PlanSet> sets,
  required String? note,
  required String? timerId,
  required double? barKg,
}) => Prescription(
  exerciseId: p.exerciseId,
  sets: sets,
  note: note == null || note.trim().isEmpty ? null : note.trim(),
  timerId: timerId,
  barKg: barKg,
);

/// Kilos per athlete in a set in kilos (Ari, 2026-11-21, `athlete_kg.dart` in maktub_core): in a plan for several
/// athletes the set has one weight per athlete in `byAthlete` and no general one.

/// [sets] ready to be typed per athlete for [athleteIds]: a set with a general weight gives it to each of them who has
/// no kilos of their own, and loses it; every other entry stays (an athlete who left keeps theirs).
List<PlanSet> withKgPerAthlete(List<PlanSet> sets, List<String> athleteIds) => [
  for (final s in sets)
    if (s.kg == null)
      s
    else
      setWith(
        s,
        reps: s.reps,
        pct: s.pct,
        kg: null,
        byAthlete: {
          ...s.byAthlete,
          for (final id in athleteIds) id: AthleteSetLoad(kg: plannedKg(s, id)),
        },
      ),
];

/// [s] with [athleteId]'s kilos set to [kg] (null removes them); the set keeps no general weight.
PlanSet setWithAthleteKg(PlanSet s, String athleteId, double? kg) => setWith(
  s,
  reps: s.reps,
  pct: s.pct,
  kg: null,
  byAthlete: {
    for (final e in s.byAthlete.entries)
      if (e.key != athleteId) e.key: e.value,
    if (kg != null) athleteId: AthleteSetLoad(kg: kg),
  },
);

/// [s] with one weight [kg] for everyone: kilos per athlete without % go, so they do not win over it in the session.
PlanSet setWithSingleKg(PlanSet s, double? kg) => setWith(
  s,
  reps: s.reps,
  pct: s.pct,
  kg: kg,
  byAthlete: {
    for (final e in s.byAthlete.entries)
      if (e.value.pct != null) e.key: e.value,
  },
);

/// The one weight of [s] shown when it is typed as a single value: what the session proposes to [athleteId] (the plan's
/// only athlete), or the general weight when there is none.
double? singleKgOf(PlanSet s, String? athleteId) => athleteId == null ? s.kg : plannedKg(s, athleteId);

/// [sets] of an exercise without weight that a plan for [athleteIds] gives kilos and no % (saving the plan makes it an
/// exercise in kilos, `weightedBySets`): the kilos go to each athlete, so the set is already typed per athlete.
/// Unchanged when any set has a %, which makes it loaded by %.
List<PlanSet> kgToEachAthlete(List<PlanSet> sets, List<String> athleteIds) =>
    sets.any((s) => (s.pct ?? 0) > 0) ? sets : withKgPerAthlete(sets, athleteIds);
