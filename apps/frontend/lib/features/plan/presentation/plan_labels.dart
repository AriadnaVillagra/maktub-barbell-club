import 'package:maktub_core/maktub_core.dart';

String planTypeLabel(PlanType type) => switch (type) {
  PlanType.regular => 'Regular',
  PlanType.test => 'Test',
};

String _number(double v) => v == v.roundToDouble()
    ? '${v.toInt()}'
    : '$v'.replaceAll('.', ',');

/// The sets as a short line: "8 × 65 %, 5 × 72,5 %"; sets without `%` show just the reps.
String setsSummary(List<PlanSet> sets) => [
  for (final s in sets)
    s.pct == null
        ? (s.maxReps ? 'Max.' : '${s.reps ?? '?'}')
        : '${s.maxReps ? 'Max.' : '${s.reps ?? '?'}'} × ${_number(s.pct!)} %',
].join(', ');
