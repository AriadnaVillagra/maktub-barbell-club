import 'package:maktub_backend/features/catalogo/delete_timer/delete_timer_store.dart';
import 'package:maktub_backend/features/catalogo/write_exercise/write_exercise_store.dart';
import 'package:maktub_core/maktub_core.dart';

import 'usage_store.dart';

/// The club a usage question is asked in: a club item only counts plans of its own club; a platform base
/// item counts plans of every club, because any club can use it.
String? _scope(String clubId) => clubId == clubPlataforma ? null : clubId;

/// Plans as usage of exercises, behind the catalog's [ExerciseUsage].
class PlanExerciseUsage implements ExerciseUsage {
  PlanExerciseUsage(this._store);

  final PlanUsageStore _store;

  @override
  Future<bool> isUsed(String clubId, String exerciseId) =>
      _store.exerciseInPlans(_scope(clubId), exerciseId);
}

/// Plans as usage of timers (block timer or prescription timer), behind the catalog's [TimerUsage].
class PlanTimerUsage implements TimerUsage {
  PlanTimerUsage(this._store);

  final PlanUsageStore _store;

  @override
  Future<bool> isUsed(String clubId, String timerId) =>
      _store.timerInPlans(_scope(clubId), timerId);
}
