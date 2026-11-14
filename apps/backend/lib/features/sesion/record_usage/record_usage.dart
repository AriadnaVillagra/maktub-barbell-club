import 'package:maktub_backend/features/catalogo/write_exercise/write_exercise_store.dart';
import 'package:maktub_core/maktub_core.dart';

import 'record_usage_store.dart';

/// Set records as usage of exercises, behind the catalog's [ExerciseUsage]. A club exercise only counts records of
/// its own club; a platform base exercise counts those of every club, because any club can train it.
class RecordExerciseUsage implements ExerciseUsage {
  RecordExerciseUsage(this._store);

  final RecordUsageStore _store;

  @override
  Future<bool> isUsed(String clubId, String exerciseId) =>
      _store.exerciseInRecords(
        clubId == clubPlataforma ? null : clubId,
        exerciseId,
      );
}
