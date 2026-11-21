import 'package:maktub_core/maktub_core.dart';

const _weekdays = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
const _months = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];
const _monthNames = [
  'Enero',
  'Febrero',
  'Marzo',
  'Abril',
  'Mayo',
  'Junio',
  'Julio',
  'Agosto',
  'Septiembre',
  'Octubre',
  'Noviembre',
  'Diciembre',
];

/// "vie 3 abr 2026".
String historyDateLabel(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]} ${d.year}';

/// "Abril 2026": the header of a month in the list.
String historyMonthLabel(DateTime d) => '${_monthNames[d.month - 1]} ${d.year}';

/// "Ciclo 1 · Semana 2 · Día 3 (Pierna)".
String historyPositionLabel(HistoryEntry e) =>
    'Ciclo ${e.cycle} · Semana ${e.week} · Día ${e.day}${e.dayName == null ? '' : ' (${e.dayName})'}';

/// The plan's name, or what is left of one that was deleted.
String historyPlanLabel(HistoryEntry e) => e.planName ?? 'Plan eliminado';

String _number(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

/// "15:04", or "1:05:00" from an hour on.
String durationLabel(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// A set's target as the coach wrote it: "5 al 70 %", "8 con 20 kg", "Máx.", "45 s", "400 m". With the athlete's
/// frozen kilos (E5.16), "5 al 70 % (72.5 kg)". Empty when it has none.
String targetLabel(PlanSet t, {String? athleteId}) {
  final parts = <String>[
    if (t.maxReps) 'Máx.' else if (t.reps != null) '${t.reps}',
    if (t.pct != null)
      'al ${_number(t.pct!)} %'
    else if (t.kg != null)
      'con ${_number(t.kg!)} kg',
    if (t.seconds != null) '${t.seconds} s',
    if (t.distanceM != null) '${_number(t.distanceM!)} m',
    if (t.calories != null) '${_number(t.calories!)} cal',
  ];
  final own = athleteId == null ? null : t.byAthlete[athleteId]?.kg;
  final label = parts.join(' ');
  if (own == null || t.kg != null) return label;
  return label.isEmpty ? '${_number(own)} kg' : '$label (${_number(own)} kg)';
}

/// What the athlete did in a set: "72.5 kg × 5", "× 12", "45 s", "400 m · 20 cal". Empty when nothing was loaded.
String recordLabel(SetRecord r) {
  final load = [
    if (r.kg != null) '${_number(r.kg!)} kg',
    if (r.reps != null) '× ${r.reps}',
  ].join(' ');
  return [
    if (load.isNotEmpty) load,
    if (r.seconds != null) '${r.seconds} s',
    if (r.distanceM != null) '${_number(r.distanceM!)} m',
    if (r.calories != null) '${_number(r.calories!)} cal',
  ].join(' · ');
}
