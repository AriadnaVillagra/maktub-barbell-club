import 'package:maktub_core/maktub_core.dart';

import '../../../core/offline/local_copy.dart';
import '../domain/catalog_repository.dart';
import '../domain/exercise_draft.dart';

/// The catalog's reads with the device's copy (E7.15), so the day's exercises have names without signal. Writes go
/// straight to the server.
class CachedCatalogRepository implements CatalogRepository {
  CachedCatalogRepository(this._remote, this._reads);

  final CatalogRepository _remote;
  final LocalCopyReads _reads;

  @override
  Future<List<Exercise>> exercises(
    String clubId, {
    String? categoryId,
    CatalogStatus? status,
  }) => _reads.read(
    copyKey(['exercises', clubId, categoryId ?? '', status?.cable ?? '']),
    () => _remote.exercises(clubId, categoryId: categoryId, status: status),
    encode: (es) => [for (final e in es) e.toJson()],
    decode: (d) => [
      for (final e in d as List)
        Exercise.fromJson((e as Map).cast<String, dynamic>()),
    ],
  );

  @override
  Future<List<Category>> categories(String clubId) => _reads.read(
    copyKey(['categories', clubId]),
    () => _remote.categories(clubId),
    encode: (cs) => [for (final c in cs) c.toJson()],
    decode: (d) => [
      for (final c in d as List)
        Category.fromJson((c as Map).cast<String, dynamic>()),
    ],
  );

  @override
  Future<List<MuscleGroup>> muscleGroups(String clubId) =>
      _remote.muscleGroups(clubId);

  @override
  Future<List<MovementPattern>> patterns(String clubId) =>
      _remote.patterns(clubId);

  @override
  Future<Exercise> createExercise(String clubId, ExerciseDraft draft) =>
      _remote.createExercise(clubId, draft);

  @override
  Future<Exercise> updateExercise(
    String clubId,
    String id,
    ExerciseDraft draft,
  ) => _remote.updateExercise(clubId, id, draft);

  @override
  Future<Exercise> setExerciseStatus(
    String clubId,
    String id,
    CatalogStatus status,
  ) => _remote.setExerciseStatus(clubId, id, status);

  @override
  Future<DeleteExerciseResult> deleteExercise(String clubId, String id) =>
      _remote.deleteExercise(clubId, id);
}
