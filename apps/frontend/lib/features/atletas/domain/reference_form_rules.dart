import 'package:maktub_core/maktub_core.dart';

/// What the sheet's edit form records.
enum ReferenceKind { rm, factor, fixedWeight }

/// Whether [kind] can be recorded for [exercise], given how the exercise is measured. RMs and work
/// factors apply to load by % of RM; a fixed weight to fixed load. Pull-ups or the bike have neither.
bool acceptsReference(ReferenceKind kind, Exercise exercise) => switch (kind) {
  ReferenceKind.rm || ReferenceKind.factor => exercise.metrics.contains(Metric.loadPctRm),
  ReferenceKind.fixedWeight => exercise.metrics.contains(Metric.fixedLoad),
};

/// A number typed by the coach (comma or point as decimal separator). Null unless it is > 0.
double? parsePositive(String text) {
  final v = double.tryParse(text.trim().replaceAll(',', '.'));
  return v != null && v.isFinite && v > 0 ? v : null;
}
