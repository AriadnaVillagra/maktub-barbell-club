import 'package:maktub_core/maktub_core.dart';

String planTypeLabel(PlanType type) => switch (type) {
  PlanType.regular => 'Regular',
  PlanType.test => 'RM',
  PlanType.history => 'Histórico',
};

String planVisibilityLabel(PlanVisibility v) => switch (v) {
  PlanVisibility.private => 'Privado',
  PlanVisibility.sharedReadOnly => 'Compartido para ver',
  PlanVisibility.sharedEditable => 'Compartido para editar',
};

/// What each visibility means for the other coaches of the club.
String planVisibilityDetail(PlanVisibility v) => switch (v) {
  PlanVisibility.private => 'Solo quien lo creó y los administradores del club lo ven.',
  PlanVisibility.sharedReadOnly =>
    'Los otros coaches lo ven, lo copian y lo asignan, pero no lo cambian.',
  PlanVisibility.sharedEditable =>
    'Los otros coaches también lo editan y lo publican. Eliminarlo y cambiar quién lo ve queda para quien lo '
    'creó y los administradores.',
};

String formatNumber(double v) =>
    v == v.roundToDouble() ? '${v.toInt()}' : '$v'.replaceAll('.', ',');

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
