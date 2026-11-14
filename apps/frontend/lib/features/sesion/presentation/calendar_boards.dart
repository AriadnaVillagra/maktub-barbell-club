import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../catalogo/presentation/catalog_admin_providers.dart'
    show clubTimersProvider;
import '../../plan/presentation/plan_labels.dart'
    show formatNumber, setsSummary;
import 'providers.dart';

/// The category whose exercises the compact grid shows as the day's main ones.
const _primaryCategoryId = 'primario';

/// One day of the cycle as the calendar shows it.
class CalendarDay {
  const CalendarDay({
    required this.week,
    required this.day,
    required this.plan,
    required this.done,
    required this.highlighted,
  });

  final int week;
  final int day;
  final PlanDay plan;
  final bool done;

  /// The day D13 opens.
  final bool highlighted;

  String get title => 'Día $day';
}

/// One week of the cycle with its model's name and days.
class CalendarWeek {
  const CalendarWeek({
    required this.week,
    required this.modelName,
    required this.current,
    required this.days,
  });

  final int week;

  /// Null when the assignment has no model for the week.
  final String? modelName;
  final bool current;
  final List<CalendarDay> days;
}

/// Every week of the cycle [data] is in, with each day done or pending as [isDone] says and the D13 day marked.
List<CalendarWeek> calendarWeeks(
  SessionDayData data, {
  required bool Function(int week, int day) isDone,
}) => [
  for (var w = 1; w <= planCycleWeeks; w++)
    CalendarWeek(
      week: w,
      modelName: data.plan.weekModelOf(w)?.name,
      current: w == data.location.week,
      days: [
        for (final (i, plan)
            in (data.plan.weekModelOf(w)?.days ?? const <PlanDay>[]).indexed)
          CalendarDay(
            week: w,
            day: i + 1,
            plan: plan,
            done: isDone(w, i + 1),
            highlighted: w == data.location.week && i + 1 == data.openingDay,
          ),
      ],
    ),
];

/// The day's main prescriptions: those of its primary blocks, else those of its first block with any.
List<Prescription> mainPrescriptions(PlanDay day) {
  final primary = [
    for (final b in day.blocks)
      if (b.categoryId == _primaryCategoryId) ...b.prescriptions,
  ];
  if (primary.isNotEmpty) return primary;
  return day.blocks
          .where((b) => b.prescriptions.isNotEmpty)
          .firstOrNull
          ?.prescriptions ??
      const [];
}

String _exerciseName(Prescription p, Map<String, String> names) {
  final id = p.exerciseId;
  return id == null ? 'Sin ejercicio' : names[id] ?? 'Ejercicio';
}

/// The week's title, its model and, for the current week, the "Esta semana" badge. [stacked] puts them one under
/// the other, for the label column of the compact grid.
class CalendarWeekHeader extends StatelessWidget {
  const CalendarWeekHeader({
    super.key,
    required this.week,
    this.stacked = false,
  });

  final CalendarWeek week;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final titleStyle = context.textos.titleSmall!.copyWith(
      color: week.current ? context.colores.enfasis : null,
    );
    final badge = week.current
        ? InsigniaMaktub(
            'Esta semana',
            context.colores.turnoActivo,
            icono: Icons.event,
          )
        : null;
    final model = week.modelName ?? 'Sin modelo';
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Espacio.xs,
        children: [
          Text('Semana ${week.week}', style: titleStyle),
          Text(
            model,
            style: context.textos.bodySmall!.copyWith(
              color: context.esquema.onSurfaceVariant,
            ),
          ),
          ?badge,
        ],
      );
    }
    return Wrap(
      spacing: Espacio.s,
      runSpacing: Espacio.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Semana ${week.week} · $model', style: titleStyle),
        ?badge,
      ],
    );
  }
}

/// An exercise and its sets, in two lines.
class _ExerciseLine extends StatelessWidget {
  const _ExerciseLine({required this.name, required this.detail});

  final String name;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Espacio.xs),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: context.textos.bodyMedium,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (detail.isNotEmpty)
          Text(
            detail,
            style: context.textos.bodySmall!.copyWith(
              color: context.esquema.onSurfaceVariant,
            ),
          ),
      ],
    ),
  );
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay();

  @override
  Widget build(BuildContext context) => Text(
    'Sin bloques',
    style: context.textos.bodySmall!.copyWith(
      color: context.esquema.onSurfaceVariant,
    ),
  );
}

/// A row of day widgets with equal heights, scrolling sideways when it does not fit.
class _DayRow extends StatelessWidget {
  const _DayRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Espacio.s,
        children: children,
      ),
    ),
  );
}

/// Compact: a grid with one row per week and one column per day. Each cell has the day's state and its main
/// exercises with their sets.
class CompactBoard extends StatelessWidget {
  const CompactBoard({
    super.key,
    required this.weeks,
    required this.names,
    required this.selected,
    required this.onSelect,
  });

  final List<CalendarWeek> weeks;
  final Map<String, String> names;
  final (int, int)? selected;
  final void Function(CalendarDay day) onSelect;

  @override
  Widget build(BuildContext context) {
    final columns = weeks.fold(
      0,
      (most, w) => w.days.length > most ? w.days.length : most,
    );
    // On a phone the week's label goes above its row, so the days get the
    // width.
    final labelsAbove = context.tamanoPantalla == TamanoPantalla.compacto;
    Widget cells(CalendarWeek week) => Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Espacio.s,
      children: [
        for (var d = 0; d < columns; d++)
          SizedBox(
            width: DayCard.cellWidth,
            child: d < week.days.length ? _cell(week.days[d]) : null,
          ),
      ],
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: labelsAbove ? Espacio.l : Espacio.s,
        children: [
          for (final week in weeks)
            if (labelsAbove)
              Column(
                key: Key('calendar-week-${week.week}'),
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Espacio.s,
                children: [
                  CalendarWeekHeader(week: week),
                  IntrinsicHeight(child: cells(week)),
                ],
              )
            else
              IntrinsicHeight(
                key: Key('calendar-week-${week.week}'),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: Espacio.s,
                  children: [
                    SizedBox(
                      width: DayCard.weekLabelWidth,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: week.current
                              ? context.esquema.surfaceContainer
                              : null,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(Radios.medio),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(Espacio.s),
                          child: CalendarWeekHeader(week: week, stacked: true),
                        ),
                      ),
                    ),
                    cells(week),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _cell(CalendarDay day) {
    final main = mainPrescriptions(day.plan);
    return DayCard(
      key: Key('calendar-day-${day.week}-${day.day}'),
      title: day.title,
      subtitle: day.plan.name,
      done: day.done,
      highlighted: day.highlighted,
      selected: selected == (day.week, day.day),
      onTap: () => onSelect(day),
      children: [
        if (main.isEmpty) const _EmptyDay(),
        for (final p in main)
          _ExerciseLine(
            name: _exerciseName(p, names),
            detail: setsSummary(p.sets),
          ),
      ],
    );
  }
}

/// Cards: per week, a row of day cards with every block and its exercises.
class CardsBoard extends StatelessWidget {
  const CardsBoard({
    super.key,
    required this.weeks,
    required this.names,
    required this.selected,
    required this.onSelect,
  });

  final List<CalendarWeek> weeks;
  final Map<String, String> names;
  final (int, int)? selected;
  final void Function(CalendarDay day) onSelect;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final week in weeks)
        Padding(
          key: Key('calendar-week-${week.week}'),
          padding: const EdgeInsets.only(bottom: Espacio.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Espacio.s,
            children: [
              CalendarWeekHeader(week: week),
              if (week.days.isEmpty)
                const _NoDays()
              else
                _DayRow(
                  children: [
                    for (final day in week.days)
                      SizedBox(
                        width: DayCard.cardWidth,
                        child: DayCard(
                          key: Key('calendar-day-${day.week}-${day.day}'),
                          title: day.title,
                          subtitle: day.plan.name,
                          done: day.done,
                          highlighted: day.highlighted,
                          selected: selected == (day.week, day.day),
                          onTap: () => onSelect(day),
                          children: [
                            if (day.plan.blocks.isEmpty) const _EmptyDay(),
                            for (final block in day.plan.blocks) ...[
                              Padding(
                                padding: const EdgeInsets.only(top: Espacio.s),
                                child: Text(
                                  block.name,
                                  style: context.textos.labelLarge,
                                ),
                              ),
                              for (final p in block.prescriptions)
                                _ExerciseLine(
                                  name: _exerciseName(p, names),
                                  detail: setsSummary(p.sets),
                                ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
    ],
  );
}

class _NoDays extends StatelessWidget {
  const _NoDays();

  @override
  Widget build(BuildContext context) => Text(
    'Esta semana no tiene días cargados.',
    style: context.textos.bodyMedium,
  );
}

/// Detailed: per week, every day in full with its button to go to its session. Days sit side by side when the width
/// allows it.
class DetailedBoard extends StatelessWidget {
  const DetailedBoard({
    super.key,
    required this.weeks,
    required this.names,
    required this.onGo,
  });

  final List<CalendarWeek> weeks;
  final Map<String, String> names;
  final void Function(int week, int day) onGo;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final perRow = (constraints.maxWidth / DayCard.detailWidth)
          .floor()
          .clamp(1, 4);
      final width =
          (constraints.maxWidth - Espacio.m * (perRow - 1)) / perRow;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final week in weeks)
            Padding(
              key: Key('calendar-week-${week.week}'),
              padding: const EdgeInsets.only(bottom: Espacio.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Espacio.s,
                children: [
                  CalendarWeekHeader(week: week),
                  if (week.days.isEmpty) const _NoDays(),
                  Wrap(
                    spacing: Espacio.m,
                    runSpacing: Espacio.m,
                    children: [
                      for (final day in week.days)
                        SizedBox(
                          width: width,
                          child: DayCard(
                            key: Key('calendar-day-${day.week}-${day.day}'),
                            title: day.title,
                            subtitle: day.plan.name,
                            done: day.done,
                            highlighted: day.highlighted,
                            action: GoToSessionButton(
                              day: day,
                              onGo: onGo,
                              prominent: false,
                            ),
                            children: [DayDetail(day: day.plan, names: names)],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

/// "Ir a la sesión de este día": the only way the calendar leaves for the session view.
class GoToSessionButton extends StatelessWidget {
  const GoToSessionButton({
    super.key,
    required this.day,
    required this.onGo,
    this.prominent = true,
  });

  final CalendarDay day;
  final void Function(int week, int day) onGo;

  /// A filled button when it is the only action on screen; outlined where
  /// every day has one.
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final key = Key('calendar-go-${day.week}-${day.day}');
    void go() => onGo(day.week, day.day);
    const icon = Icon(Icons.play_arrow);
    const label = Text('Ir a la sesión de este día');
    return prominent
        ? FilledButton.icon(key: key, onPressed: go, icon: icon, label: label)
        : OutlinedButton.icon(
            key: key,
            onPressed: go,
            icon: icon,
            label: label,
          );
  }
}

/// Everything the plan says for a day: each block with its name, note and timer, and each prescription with its
/// sets (reps, %, fixed kilos), note, bar and timer.
class DayDetail extends ConsumerWidget {
  const DayDetail({super.key, required this.day, required this.names});

  final PlanDay day;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timers = ref.watch(clubTimersProvider).value ?? const [];
    String? timerName(String? id) =>
        timers.where((t) => t.id == id).firstOrNull?.nombre;
    final muted = context.textos.bodySmall!.copyWith(
      color: context.esquema.onSurfaceVariant,
    );
    if (day.blocks.isEmpty) {
      return Text(
        'Este día no tiene bloques.',
        style: context.textos.bodyMedium,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in day.blocks) ...[
          Padding(
            padding: const EdgeInsets.only(top: Espacio.m),
            child: Text(block.name, style: context.textos.titleSmall),
          ),
          if (block.note case final note? when note.isNotEmpty)
            Text(note, style: muted),
          if (timerName(block.timerId) case final timer?)
            _TimerLine(name: timer),
          for (final p in block.prescriptions)
            _ExerciseLine(
              name: _exerciseName(p, names),
              detail: [
                if (p.sets.isNotEmpty) setsSummary(p.sets),
                if (p.barKg case final bar?) 'barra de ${formatNumber(bar)} kg',
                if (p.note case final note? when note.isNotEmpty) note,
                if (timerName(p.timerId) case final timer?)
                  'temporizador: $timer',
              ].join(' · '),
            ),
        ],
      ],
    );
  }
}

class _TimerLine extends StatelessWidget {
  const _TimerLine({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final style = context.textos.bodySmall!.copyWith(
      color: context.esquema.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(top: Espacio.xs),
      child: Row(
        spacing: Espacio.xs,
        children: [
          Icon(Icons.timer_outlined, size: style.fontSize, color: style.color),
          Flexible(child: Text(name, style: style)),
        ],
      ),
    );
  }
}
