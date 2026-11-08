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
