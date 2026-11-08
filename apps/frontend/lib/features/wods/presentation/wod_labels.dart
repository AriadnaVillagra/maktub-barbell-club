import 'package:maktub_core/maktub_core.dart';

/// "3 ejercicios · Temporizador: EMOM 10" under a WoD's name; [timerName] is the timer's name when known.
String wodSummary(Wod wod, {String? timerName}) {
  final count = wod.prescriptions.length;
  return [
    count == 1 ? '1 ejercicio' : '$count ejercicios',
    if (wod.timerId != null) 'Temporizador: ${timerName ?? wod.timerId}',
  ].join(' · ');
}
