import 'package:maktub_core/maktub_core.dart';

import 'exercise_draft.dart';

/// Reads the catalog visible to a club (base entries plus the club's own): `GET /clubes/{id}/catalogo/...`.
/// Shared by the exercise picker (E2.10) and the catalog screens (E2.8).
abstract interface class CatalogRepository {
  /// Exercises visible to [clubId], by name. Both states when [status] is null.
  Future<List<Exercise>> exercises(
    String clubId, {
    String? categoryId,
    CatalogStatus? status,
  });

  Future<List<Category>> categories(String clubId);

  Future<List<MuscleGroup>> muscleGroups(String clubId);

  Future<List<MovementPattern>> patterns(String clubId);

  /// Creates an exercise of the club (E2.4). Throws `ErrorDeApi` with the backend's message on failure.
  Future<Exercise> createExercise(String clubId, ExerciseDraft draft);

  /// Replaces the editable fields of the club's exercise [id]; its status is kept.
  Future<Exercise> updateExercise(
    String clubId,
    String id,
    ExerciseDraft draft,
  );

  Future<Exercise> setExerciseStatus(
    String clubId,
    String id,
    CatalogStatus status,
  );

  /// Deletes the exercise, or archives it when it is already in use.
  Future<DeleteExerciseResult> deleteExercise(String clubId, String id);
}

class DeleteExerciseResult {
  const DeleteExerciseResult({required this.deleted, this.archived});

  final bool deleted;

  /// The archived exercise when it was in use and could not be deleted.
  final Exercise? archived;
}
