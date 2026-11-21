import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../asignacion/domain/calendar_repository.dart' show DayState;
import '../domain/calendar_layout.dart';
import 'calendar_boards.dart';
import 'providers.dart';
import 'session_loads_view.dart' show SessionAthleteSelector;

/// The day states of the cycle [data] is in, as [athleteId] (the tab on screen) did it, kept current as sets are
/// recorded. Empty while loading.
List<DayState> watchDayStates(
  WidgetRef ref,
  SessionDayData data,
  String? athleteId,
) =>
    ref
        .watch(
          cycleDayStatesProvider((
            data.clubId,
            data.location.assignmentId,
            data.location.startDate,
            data.location.cycle,
            athleteId,
          )),
        )
        .value ??
    const [];

/// The state of the day of the current cycle; null when nothing says it (pending).
DayState? dayStateOf(
  List<DayState> states,
  SessionDayData data,
  int week,
  int day,
) => states
    .where(
      (s) => s.cycle == data.location.cycle && s.week == week && s.day == day,
    )
    .firstOrNull;

/// The whole plan as a board (E7.25): the plan's name and cycle, a selector of the layout, remembered on the device,
/// and every week of the cycle laid out compact, as cards or in full. Each day shows how far the athlete on screen got
/// (with a selector of the athlete when the plan has more than one),
/// and the day D13 would open is highlighted. Tapping a day in the compact or cards layout opens its detail right
/// there, at the bottom on a phone and at the side from a medium screen. Only "Ir a la sesión de este día" leaves,
/// calling [onPick] with its week and day.
class SessionCalendarView extends ConsumerStatefulWidget {
  const SessionCalendarView({
    super.key,
    required this.data,
    required this.onPick,
    required this.viewToggle,
  });

  final SessionDayData data;
  final void Function(int week, int day) onPick;

  /// Day or calendar, the first row of the header card.
  final Widget viewToggle;

  @override
  ConsumerState<SessionCalendarView> createState() =>
      _SessionCalendarViewState();
}

class _SessionCalendarViewState extends ConsumerState<SessionCalendarView> {
  /// The week and day whose detail is open.
  (int, int)? _selected;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final screen = ref.watch(sessionScreenProvider);
    final athleteId = athleteOnScreen(data, screen);
    final states = watchDayStates(ref, data, athleteId);
    final layout = ref.watch(calendarLayoutProvider);
    final weeks = calendarWeeks(
      data,
      stateOf: (w, d) => dayStateOf(states, data, w, d),
    );
    final names = data.exerciseNames;
    final daysPerWeek = weeks.fold(
      0,
      (most, w) => w.days.length > most ? w.days.length : most,
    );
    final phone = context.tamanoPantalla == TamanoPantalla.compacto;
    // Tapping the selected day again unselects it.
    void select(CalendarDay day) => setState(
      () => _selected = _selected == (day.week, day.day)
          ? null
          : (day.week, day.day),
    );

    final board = ListView(
      padding: const EdgeInsets.all(Espacio.l),
      children: [
        // Compact on purpose (Ari): view, then the plan, then the layout.
        Card(
          key: const Key('calendar-header'),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(Espacio.s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Espacio.s,
              children: [
                widget.viewToggle,
                // Each athlete's days are their own: the tab chosen here is the session's.
                if (data.memberIds.length > 1)
                  SessionAthleteSelector(
                    keyPrefix: 'calendar',
                    data: data,
                    selected: athleteId,
                    onSelect: ref
                        .read(sessionScreenProvider.notifier)
                        .selectAthlete,
                  ),
                Wrap(
                  spacing: Espacio.s,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      data.plan.name,
                      key: const Key('calendar-plan'),
                      style: context.textos.labelLarge,
                    ),
                    Text(
                      'Ciclo ${data.location.cycle} · $planCycleWeeks semanas · '
                      '$daysPerWeek días por semana',
                      key: const Key('calendar-summary'),
                      style: context.textos.bodySmall,
                    ),
                  ],
                ),
                SegmentedButton<CalendarLayout>(
                  key: const Key('calendar-layout'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: [
                    for (final (value, icon, label) in [
                      (CalendarLayout.compact, Icons.grid_view, 'Compacta'),
                      (
                        CalendarLayout.cards,
                        Icons.view_carousel_outlined,
                        'Tarjetas',
                      ),
                      (
                        CalendarLayout.detailed,
                        Icons.view_agenda_outlined,
                        'Detallada',
                      ),
                    ])
                      ButtonSegment(
                        value: value,
                        // On a phone the three labels only fit without icons.
                        icon: phone ? null : Icon(icon),
                        label: Text(label),
                      ),
                  ],
                  selected: {layout},
                  onSelectionChanged: (l) =>
                      ref.read(calendarLayoutProvider.notifier).choose(l.first),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Espacio.m),
        switch (layout) {
          CalendarLayout.compact => CompactBoard(
            weeks: weeks,
            names: names,
            selected: _selected,
            onSelect: select,
          ),
          CalendarLayout.cards => CardsBoard(
            weeks: weeks,
            names: names,
            selected: _selected,
            onSelect: select,
            onGo: widget.onPick,
          ),
          CalendarLayout.detailed => DetailedBoard(
            weeks: weeks,
            names: names,
            onGo: widget.onPick,
          ),
        },
      ],
    );
    // Only the compact grid needs the panel: a card or a detailed day already shows the whole day.
    if (layout != CalendarLayout.compact) return board;

    final selected = [for (final w in weeks) ...w.days]
        .where((d) => (d.week, d.day) == _selected)
        .firstOrNull;
    if (!phone) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: board),
          const VerticalDivider(width: Borde.fino, thickness: Borde.fino),
          SizedBox(
            width: DayCard.detailWidth,
            child: selected == null
                ? const _PanelHint()
                : _DayPanel(day: selected, names: names, onGo: widget.onPick),
          ),
        ],
      );
    }
    return Column(
      children: [
        Expanded(child: board),
        if (selected != null)
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height / 2,
            ),
            child: _DayPanel(
              day: selected,
              names: names,
              onGo: widget.onPick,
              onClose: () => setState(() => _selected = null),
            ),
          ),
      ],
    );
  }
}

class _PanelHint extends StatelessWidget {
  const _PanelHint();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Espacio.xl),
      child: Text(
        'Tocá un día para ver su detalle.',
        key: const Key('calendar-detail-hint'),
        style: context.textos.bodyMedium!.copyWith(
          color: context.esquema.onSurfaceVariant,
        ),
        textAlign: TextAlign.center,
      ),
    ),
  );
}

/// The detail of the tapped day, with its button to go to its session. [onClose] adds a button to close it.
class _DayPanel extends StatelessWidget {
  const _DayPanel({
    required this.day,
    required this.names,
    required this.onGo,
    this.onClose,
  });

  final CalendarDay day;
  final Map<String, String> names;
  final void Function(int week, int day) onGo;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final name = day.plan.name;
    return Material(
      key: const Key('calendar-detail'),
      color: context.esquema.surfaceContainer,
      shape: onClose == null
          ? null
          : Border(
              top: BorderSide(
                color: context.esquema.outlineVariant,
                width: Borde.fino,
              ),
            ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Espacio.l,
          Espacio.s,
          Espacio.s,
          Espacio.l,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      'Semana ${day.week}',
                      day.title,
                      if (name != null && name.isNotEmpty) name,
                    ].join(' · '),
                    key: const Key('calendar-detail-title'),
                    style: context.textos.titleMedium,
                  ),
                ),
                if (onClose case final close?)
                  IconButton(
                    key: const Key('calendar-detail-close'),
                    tooltip: 'Cerrar',
                    onPressed: close,
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(right: Espacio.s),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: Espacio.s),
                    Wrap(
                      spacing: Espacio.xs,
                      runSpacing: Espacio.xs,
                      children: [
                        DayStatusBadge(
                          done: day.done,
                          doneSets: day.doneSets,
                          totalSets: day.totalSets,
                        ),
                        if (day.highlighted)
                          InsigniaMaktub(
                            DayCard.nextLabel,
                            context.colores.turnoActivo,
                            icono: Icons.arrow_forward,
                          ),
                      ],
                    ),
                    DayDetail(day: day.plan, names: names),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Espacio.m),
            Padding(
              padding: const EdgeInsets.only(right: Espacio.s),
              child: GoToSessionButton(day: day, onGo: onGo),
            ),
          ],
        ),
      ),
    );
  }
}
