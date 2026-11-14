import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../catalogo/presentation/catalog_admin_widgets.dart'
    show asyncView, showApiError;
import '../../plan/presentation/plan_labels.dart' show setsSummary;
import '../../access/presentation/providers.dart' show canPlanProvider;
import 'providers.dart';
import 'session_block_card.dart';
import 'session_calendar_view.dart';
import 'session_loads_view.dart';
import 'session_timers.dart';

/// The two views of the screen.
enum SessionView { day, calendar }

/// The day's session and the plan's calendar on one screen (E7.24). A selector switches between the session of
/// the day (opens on the day D13 gives, lets the user pick another one and the present athletes, and once open
/// shows each present athlete's kilos with their day adjustment) and the calendar of the whole cycle.
class SessionPage extends ConsumerStatefulWidget {
  const SessionPage({
    super.key,
    this.guidedPath,
    this.assignmentsPath,
    this.initialView = SessionView.day,
  });

  /// Where "Entrenar" goes, the guided mode (E7.20); without it there is no button.
  final String? guidedPath;

  /// Where a coach goes to assign a plan when there is none; without it there is no button.
  final String? assignmentsPath;

  final SessionView initialView;

  @override
  ConsumerState<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends ConsumerState<SessionPage> {
  late SessionView _view = widget.initialView;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(sessionDayProvider);
    // The calendar view picks a day for the session view, so the screen's state must outlive the session view.
    ref.listen(sessionScreenProvider, (_, _) {});
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sesión'),
        actions: const [SessionTimerButton()],
      ),
      body: asyncView(
        data,
        onRetry: () => ref.invalidate(sessionDayProvider),
        builder: (data) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Espacio.l,
                Espacio.m,
                Espacio.l,
                0,
              ),
              child: SegmentedButton<SessionView>(
                key: const Key('session-view'),
                segments: const [
                  ButtonSegment(
                    value: SessionView.day,
                    label: Text('Sesión del día'),
                  ),
                  ButtonSegment(
                    value: SessionView.calendar,
                    label: Text('Calendario'),
                  ),
                ],
                selected: {_view},
                onSelectionChanged: (v) => setState(() => _view = v.first),
              ),
            ),
            Expanded(
              child: data == null
                  ? _NoAssignment(assignmentsPath: widget.assignmentsPath)
                  : switch (_view) {
                      SessionView.day => _SessionBody(
                        data: data,
                        guidedPath: widget.guidedPath,
                      ),
                      SessionView.calendar => SessionCalendarView(
                        data: data,
                        onPick: (week, day) {
                          ref
                              .read(sessionScreenProvider.notifier)
                              .selectDay(week, day);
                          setState(() => _view = SessionView.day);
                        },
                      ),
                    },
            ),
          ],
        ),
      ),
    );
  }
}

class _NoAssignment extends ConsumerWidget {
  const _NoAssignment({this.assignmentsPath});

  final String? assignmentsPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = assignmentsPath;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Espacio.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: Espacio.m,
          children: [
            Text(
              'Todavía no hay un plan asignado',
              key: const Key('session-empty'),
              style: context.textos.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (path != null && (ref.watch(canPlanProvider) ?? false))
              FilledButton(
                key: const Key('session-go-assignments'),
                onPressed: () => context.go(path),
                child: const Text('Ir a Asignaciones'),
              ),
          ],
        ),
      ),
    );
  }
}

class _SessionBody extends ConsumerWidget {
  const _SessionBody({required this.data, this.guidedPath});

  final SessionDayData data;
  final String? guidedPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sessionScreenProvider);
    final notifier = ref.read(sessionScreenProvider.notifier);
    final location = data.location;
    final plan = data.plan;
    final week = state.week ?? location.week;
    final model = plan.weekModelOf(week);
    final dayCount = model?.days.length ?? 0;
    final day = (state.day ?? data.openingDay).clamp(
      1,
      dayCount < 1 ? 1 : dayCount,
    );
    final planDay = model != null && day <= dayCount
        ? model.days[day - 1]
        : null;
    final live = state.live;
    final dayStates = watchDayStates(ref, data);

    return ListView(
      padding: const EdgeInsets.all(Espacio.l),
      children: [
        Text(
          '${plan.name} · ciclo ${location.cycle} · semana ${location.week}',
          key: const Key('session-location'),
          style: context.textos.titleMedium,
        ),
        const SizedBox(height: Espacio.m),
        Text('Semana', style: context.textos.labelLarge),
        const SizedBox(height: Espacio.s),
        Wrap(
          spacing: Espacio.s,
          runSpacing: Espacio.s,
          children: [
            for (var w = 1; w <= planCycleWeeks; w++)
              PildoraMaktub(
                key: Key('session-week-$w'),
                texto: 'S$w',
                detalle: plan.weekModelOf(w)?.name,
                seleccionada: w == week,
                onTap: () => notifier.selectWeek(w),
              ),
          ],
        ),
        const SizedBox(height: Espacio.m),
        Text('Día', style: context.textos.labelLarge),
        const SizedBox(height: Espacio.s),
        if (dayCount == 0)
          Text(
            'Esta semana no tiene días cargados.',
            key: const Key('session-no-days'),
            style: context.textos.bodyMedium,
          )
        else
          Wrap(
            spacing: Espacio.s,
            runSpacing: Espacio.s,
            children: [
              for (var d = 1; d <= dayCount; d++)
                PildoraMaktub(
                  key: Key('session-day-$d'),
                  texto: 'Día $d',
                  detalle: isDayDone(dayStates, data, week, d)
                      ? 'Hecho'
                      : 'Pendiente',
                  seleccionada: d == day,
                  onTap: () => notifier.selectDay(week, d),
                ),
            ],
          ),
        if (planDay != null) ...[
          const SizedBox(height: Espacio.l),
          Text(
            planDay.name == null || planDay.name!.isEmpty
                ? 'Día $day'
                : 'Día $day · ${planDay.name}',
            key: const Key('session-day-title'),
            style: context.textos.titleLarge,
          ),
          if (live == null) ...[
            _PresentPicker(data: data),
            const SizedBox(height: Espacio.m),
            _OpenButton(data: data, week: week, day: day),
            for (final block in planDay.blocks)
              _BlockPreview(block: block, names: data.exerciseNames),
          ] else ...[
            if (guidedPath case final path?) ...[
              const SizedBox(height: Espacio.m),
              FilledButton.icon(
                key: const Key('session-train'),
                onPressed: () => context.push(path),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Entrenar'),
              ),
            ],
            SessionLoadsView(data: data, live: live, day: planDay),
          ],
        ],
      ],
    );
  }
}

/// Who is present by default: the user, if they are in the group; a coach who is not starts with nobody.
Set<String> _defaultPresent(SessionDayData data) => {
  if (data.ownAthleteId != null &&
      data.group.memberIds.contains(data.ownAthleteId))
    data.ownAthleteId!,
};

Set<String> _presentOf(SessionScreenState state, SessionDayData data) =>
    state.present ?? _defaultPresent(data);

class _PresentPicker extends ConsumerWidget {
  const _PresentPicker({required this.data});

  final SessionDayData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sessionScreenProvider);
    final notifier = ref.read(sessionScreenProvider.notifier);
    final present = _presentOf(state, data);
    return Padding(
      padding: const EdgeInsets.only(top: Espacio.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Presentes', style: context.textos.labelLarge),
          const SizedBox(height: Espacio.s),
          Wrap(
            spacing: Espacio.s,
            runSpacing: Espacio.s,
            children: [
              for (final id in data.group.memberIds)
                PildoraMaktub(
                  key: Key('session-present-$id'),
                  texto: athleteLabel(data, id),
                  seleccionada: present.contains(id),
                  onTap: () => notifier.setPresent(
                    present.contains(id)
                        ? ({...present}..remove(id))
                        : {...present, id},
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OpenButton extends ConsumerWidget {
  const _OpenButton({
    required this.data,
    required this.week,
    required this.day,
  });

  final SessionDayData data;
  final int week;
  final int day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sessionScreenProvider);
    final present = _presentOf(state, data);
    return FilledButton(
      key: const Key('session-open'),
      onPressed: state.opening || present.isEmpty
          ? null
          : () async {
              try {
                await ref
                    .read(sessionScreenProvider.notifier)
                    .open(data, week: week, day: day, present: present);
              } catch (e) {
                if (context.mounted) showApiError(context, e);
              }
            },
      child: const Text('Abrir sesión'),
    );
  }
}

class _BlockPreview extends StatelessWidget {
  const _BlockPreview({required this.block, required this.names});

  final PlanBlock block;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) => SessionBlockCard(
    block: block,
    children: [
      for (final p in block.prescriptions)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(names[p.exerciseId] ?? 'Ejercicio'),
          subtitle: p.sets.isEmpty ? null : Text(setsSummary(p.sets)),
        ),
    ],
  );
}

/// The athlete's name, when the user can see names; otherwise "Yo" for themselves and a neutral label.
String athleteLabel(SessionDayData data, String id) {
  final name = data.athleteNames[id];
  if (name != null) return name;
  if (id == data.ownAthleteId) return 'Yo';
  return 'Atleta ${data.group.memberIds.indexOf(id) + 1}';
}
