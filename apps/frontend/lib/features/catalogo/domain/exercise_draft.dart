import 'package:maktub_core/maktub_core.dart';

/// What the exercise form shows as the bar of an exercise that stores [barKg]. One with no bar set
/// shows what it actually uses: the club's bar if it loads by % of RM, and no bar otherwise.
double barChoice(
  double? barKg, {
  required Iterable<Metric> metrics,
  required double clubBarKg,
}) => barKg ?? (metrics.contains(Metric.loadPctRm) ? clubBarKg : noBarKg);

/// The editable fields of an exercise, as the create/edit form handles them and the API receives
/// them. The server sets `id`, `clubId`, `estado` and `auditoria`.
class ExerciseDraft {
  const ExerciseDraft({
    required this.name,
    this.categoryIds = const [],
    this.metrics = const [],
    this.defaultMetric,
    this.patternId,
    this.muscles = const [],
    this.loadReference = const LoadReference.none(),
    this.suggestionIds = const [],
    this.notes,
    this.barKg,
  });

  factory ExerciseDraft.from(Exercise e, {String? name}) => ExerciseDraft(
    name: name ?? e.name,
    categoryIds: e.categoryIds,
    metrics: e.metrics,
    defaultMetric: e.defaultMetric,
    patternId: e.patternId,
    muscles: e.muscles,
    loadReference: e.loadReference,
    suggestionIds: e.suggestionIds,
    notes: e.notes,
    barKg: e.barKg,
  );

  final String name;
  final List<String> categoryIds;
  final List<Metric> metrics;
  final Metric? defaultMetric;
  final String? patternId;
  final List<MuscleShare> muscles;
  final LoadReference loadReference;
  final List<String> suggestionIds;
  final String? notes;
  final double? barKg;

  Json toJson() => {
    'nombre': name.trim(),
    'categorias': categoryIds,
    'metricas': [for (final m in metrics) m.cable],
    'metricaObjetivo': ?defaultMetric?.cable,
    'patronId': ?patternId,
    'musculos': [for (final m in muscles) m.toJson()],
    'referencia': loadReference.toJson(),
    'sugerencias': suggestionIds,
    'notas': ?(notes == null || notes!.trim().isEmpty ? null : notes!.trim()),
    'barraKg': ?barKg,
  };
}
