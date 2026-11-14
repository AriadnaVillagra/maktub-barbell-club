import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../asignacion/domain/calendar_repository.dart' show DayState;
import 'providers.dart';

/// The day states of the cycle [data] is in, kept current as sets are recorded. Empty while loading.
List<DayState> watchDayStates(WidgetRef ref, SessionDayData data) =>
    ref
        .watch(
          cycleDayStatesProvider((
            data.clubId,
            data.group.id,
            data.location.startDate,
            data.location.cycle,
          )),
        )
        .value ??
    const [];

/// Whether the day of the current cycle has sets recorded; false when nothing says so.
bool isDayDone(List<DayState> states, SessionDayData data, int week, int day) =>
    states.any(
      (s) =>
          s.cycle == data.location.cycle &&
          s.week == week &&
          s.day == day &&
          s.done,
    );

/// The whole plan at a glance: every week of the cycle with its model and its days done or pending. The day D13
/// would open is highlighted; tapping a day calls [onPick] with its week and day.
class SessionCalendarView extends ConsumerWidget {
  const SessionCalendarView({
    super.key,
    required this.data,
    required this.onPick,
  });

  final SessionDayData data;
  final void Function(int week, int day) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final states = watchDayStates(ref, data);
    final plan = data.plan;
    final location = data.location;
    final daysPerWeek = [
      for (var w = 1; w <= planCycleWeeks; w++)
        plan.weekModelOf(w)?.days.length ?? 0,
    ].reduce((a, b) => a > b ? a : b);
    return ListView(
      padding: const EdgeInsets.all(Espacio.l),
      children: [
        Text(
          plan.name,
          key: const Key('calendar-plan'),
          style: context.textos.titleLarge,
        ),
        Text(
          'Ciclo ${location.cycle} · $planCycleWeeks semanas · '
          '$daysPerWeek días por semana',
          key: const Key('calendar-summary'),
          style: context.textos.bodyMedium,
        ),
        const SizedBox(height: Espacio.l),
        Text('Semanas del ciclo', style: context.textos.labelLarge),
        for (var w = 1; w <= planCycleWeeks; w++) ...[
          const SizedBox(height: Espacio.m),
          Text(
            [
              'Semana $w',
              ?plan.weekModelOf(w)?.name,
              if (w == location.week) 'esta semana',
            ].join(' · '),
            key: Key('calendar-week-title-$w'),
            style: context.textos.titleSmall,
          ),
          const SizedBox(height: Espacio.s),
          Wrap(
            spacing: Espacio.s,
            runSpacing: Espacio.s,
            children: [
              for (
                var d = 1;
                d <= (plan.weekModelOf(w)?.days.length ?? 0);
                d++
              )
                PildoraMaktub(
                  key: Key('calendar-day-$w-$d'),
                  texto: 'Día $d',
                  detalle: isDayDone(states, data, w, d)
                      ? 'Hecho'
                      : 'Pendiente',
                  seleccionada: w == location.week && d == data.openingDay,
                  onTap: () => onPick(w, d),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
