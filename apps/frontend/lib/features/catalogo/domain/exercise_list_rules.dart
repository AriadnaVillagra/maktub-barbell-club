import 'package:maktub_core/maktub_core.dart';

import 'exercise_picker_rules.dart';

/// What the catalog list shows: exercises visible to [clubId] in [categoryId] (all when null) whose
/// name contains [query]. Shows the active ones, or only the archived ones when [showArchived]. Sorted by name.
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
          e.isActive != showArchived &&
          (categoryId == null || e.categoryIds.contains(categoryId)) &&
          (q.isEmpty || normalizeForSearch(e.name).contains(q)))
        e,
  ];
  return matches..sort(
    (a, b) => normalizeForSearch(a.name).compareTo(normalizeForSearch(b.name)),
  );
}

/// Exercises that [exerciseId] can take as load reference: active, visible, and measured like it, so a
/// press never offers a bike. With [defaultMetric] they must share it; without one, share some metric of
/// [metrics]. Keeps every candidate while nothing is chosen yet. [baseOnly] for a default exercise.
List<Exercise> referenceCandidates(
  List<Exercise> exercises, {
  required String clubId,
  String? exerciseId,
  Metric? defaultMetric,
  Set<Metric> metrics = const {},
  bool baseOnly = false,
}) => [
  for (final e in exercises)
    if (e.id != exerciseId &&
        e.isActive &&
        isVisibleTo(e, clubId) &&
        (!baseOnly || e.scope == CatalogScope.base) &&
        (defaultMetric != null ? e.defaultMetric == defaultMetric : metrics.isEmpty || e.metrics.any(metrics.contains)))
      e,
];
