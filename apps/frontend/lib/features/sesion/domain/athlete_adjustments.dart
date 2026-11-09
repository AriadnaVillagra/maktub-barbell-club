import 'package:maktub_core/maktub_core.dart';

/// The base categories of the blocks whose exercises can be adjusted one by one.
const _adjustableCategoryIds = {'primario', 'secundario', 'accesorio'};

/// Whether [block] offers a per-exercise adjustment: in a warm-up or a stretch it means nothing.
bool blockTakesAdjustment(PlanBlock block) =>
    _adjustableCategoryIds.contains(block.categoryId);

/// One athlete's day adjustment in its two levels (session and per exercise). Immutable and independent of
/// every other athlete's; it never touches a saved reference.
class AthleteAdjustments {
  const AthleteAdjustments({
    this.session = Ajuste.neutro,
    this.exercises = const {},
  });

  /// The session level, 50 to 150 (100 is neutral).
  final int session;

  /// The exercise level of the exercises that have one, by exercise id.
  final Map<String, int> exercises;

  /// The level in force for [exerciseId].
  int effectiveFor(String exerciseId) =>
      effectiveAdjustment(session: session, exercise: exercises[exerciseId]);

  /// After moving the session level by [delta] (0 resets it).
  AthleteAdjustments stepSession(int delta) => AthleteAdjustments(
    session: nextSessionAdjustment(session, delta),
    exercises: exercises,
  );

  /// After moving the level of [exerciseId] by [delta] (0 removes it, so it inherits the session's again).
  AthleteAdjustments stepExercise(String exerciseId, int delta) {
    final next = nextExerciseAdjustment(
      exercise: exercises[exerciseId],
      session: session,
      delta: delta,
    );
    final updated = Map<String, int>.of(exercises);
    if (next == null) {
      updated.remove(exerciseId);
    } else {
      updated[exerciseId] = next;
    }
    return AthleteAdjustments(session: session, exercises: updated);
  }

  @override
  bool operator ==(Object other) =>
      other is AthleteAdjustments &&
      other.session == session &&
      other.exercises.length == exercises.length &&
      exercises.entries.every((e) => other.exercises[e.key] == e.value);

  @override
  int get hashCode => Object.hash(
    session,
    Object.hashAllUnordered(
      exercises.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}
