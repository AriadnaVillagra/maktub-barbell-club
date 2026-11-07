import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../../access/presentation/providers.dart';
import 'providers.dart';

/// Every exercise visible to the active club, active and archived (the list filters them).
final catalogExercisesProvider = FutureProvider<List<Exercise>>((ref) async {
  final clubId = await ref
      .watch(meProvider.future)
      .then((me) => me?.activeClub?.club.id);
  if (clubId == null) return const [];
  return ref.watch(catalogRepositoryProvider).exercises(clubId);
});

final catalogCategoriesProvider = FutureProvider<List<Category>>((ref) async {
  final clubId = await ref
      .watch(meProvider.future)
      .then((me) => me?.activeClub?.club.id);
  if (clubId == null) return const [];
  return ref.watch(catalogRepositoryProvider).categories(clubId);
});

final muscleGroupsProvider = FutureProvider<List<MuscleGroup>>((ref) async {
  final clubId = await ref
      .watch(meProvider.future)
      .then((me) => me?.activeClub?.club.id);
  if (clubId == null) return const [];
  return ref.watch(catalogRepositoryProvider).muscleGroups(clubId);
});

final movementPatternsProvider = FutureProvider<List<MovementPattern>>((
  ref,
) async {
  final clubId = await ref
      .watch(meProvider.future)
      .then((me) => me?.activeClub?.club.id);
  if (clubId == null) return const [];
  return ref.watch(catalogRepositoryProvider).patterns(clubId);
});

/// Reloads the exercise lists after a write.
void refreshExercises(WidgetRef ref) {
  ref.invalidate(catalogExercisesProvider);
  ref.invalidate(activeExercisesProvider);
}
