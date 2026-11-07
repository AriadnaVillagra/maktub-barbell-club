import 'package:maktub_core/maktub_core.dart';

import 'exercise_picker_rules.dart';

/// What the catalog list shows: exercises visible to [clubId] in [categoryId] (all when null) whose
/// name contains [query]. Archived ones only when [showArchived]. Sorted by name.
List<Exercise> listedExercises(
  List<Exercise> exercises, {
  required String clubId,
  String? categoryId,
  String query = '',
  bool showArchived = false,
}) {
  final q = normalizeForSearch(query);
  final matches = [
    for (final e in exercises)
      if (isVisibleTo(e, clubId) &&
          (showArchived || e.isActive) &&
          (categoryId == null || e.categoryIds.contains(categoryId)) &&
          (q.isEmpty || normalizeForSearch(e.name).contains(q)))
        e,
  ];
  return matches..sort(
    (a, b) => normalizeForSearch(a.name).compareTo(normalizeForSearch(b.name)),
  );
}
