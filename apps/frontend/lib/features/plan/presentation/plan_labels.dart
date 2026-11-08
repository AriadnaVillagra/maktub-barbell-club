import 'package:maktub_core/maktub_core.dart';

String planTypeLabel(PlanType type) => switch (type) {
  PlanType.regular => 'Regular',
  PlanType.test => 'RM',
};

String formatNumber(double v) => v == v.roundToDouble()
    ? '${v.toInt()}'
    : '$v'.replaceAll('.', ',');

/// One set as "10", "10 al 65 %", "10 con 12,5 kg" or "Máx.".
String _setLabel(PlanSet s) {
  final reps = s.maxReps ? 'Máx.' : '${s.reps ?? '?'}';
  if (s.pct != null) return '$reps al ${formatNumber(s.pct!)} %';
  if (s.kg != null) return '$reps con ${formatNumber(s.kg!)} kg';
  return reps;
}

/// The sets as a coach writes them, with equal consecutive sets together: "3x10",
/// "1x8 al 65 %, 1x5 al 72,5 %, 2x3 al 80 %".
String setsSummary(List<PlanSet> sets) {
  final groups = <(int, String)>[];
  for (final label in sets.map(_setLabel)) {
    if (groups.isNotEmpty && groups.last.$2 == label) {
      groups.last = (groups.last.$1 + 1, label);
    } else {
      groups.add((1, label));
    }
  }
  return groups.map((g) => '${g.$1}x${g.$2}').join(', ');
}
