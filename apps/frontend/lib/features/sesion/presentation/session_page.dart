import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../catalogo/presentation/catalog_admin_widgets.dart' show asyncView;
import '../../plan/presentation/plan_labels.dart' show setsSummary;
import '../../access/presentation/providers.dart' show canPlanProvider;
import '../domain/live_session_sync.dart' show LiveStatus;
import '../domain/session_draft_store.dart' show isLocalSessionId;
import '../../../core/offline/local_copy_providers.dart';
import 'providers.dart';
import 'session_block_card.dart';
import 'session_calendar_view.dart';
import 'session_loads_view.dart';
import 'session_timers.dart';

/// The two views of the screen.
enum SessionView { day, calendar }

/// The day's session and the plan's calendar on one screen (E7.24). A selector switches between the session of
/// the day (opens on the day D13 gives, lets the user pick another one, and shows each athlete of the group in a tab
/// with their kilos to mark and edit; the session is created by the first write, E7.27) and the calendar of the
/// whole cycle.
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
    // "Entrenar" sits next to the timer (Ari), while the chosen day has something to do.
    final day = data.value;
    final path = widget.guidedPath;
    var canTrain = false;
    if (day != null && path != null) {
      final (:week, day: dayNumber) = shownDayOf(
        day,
        ref.watch(sessionScreenProvider),
      );
      canTrain = planDayOf(day, week, dayNumber) != null;
    }
    // Day or calendar: the first row of each view's header card (Ari: everything took too much room).
    final viewToggle = SegmentedButton<SessionView>(
      key: const Key('session-view'),
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: const [
        ButtonSegment(value: SessionView.day, label: Text('Sesión del día')),
        ButtonSegment(value: SessionView.calendar, label: Text('Calendario')),
      ],
      selected: {_view},
      onSelectionChanged: (v) => setState(() => _view = v.first),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sesión'),
        actions: [
          if (canTrain)
            FilledButton.icon(
              key: const Key('session-train'),
              onPressed: () => context.go(path!),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Entrenar'),
            ),
          const SessionTimerButton(),
        ],
      ),
      body: asyncView(
        data,
        onRetry: () => ref.invalidate(sessionDayProvider),
        builder: (data) => Column(
          children: [
            const LocalCopyNotice(),
            if (data != null) _PlanPicker(current: data),
            Expanded(
              child: data == null
                  ? _NoAssignment(assignmentsPath: widget.assignmentsPath)
                  : switch (_view) {
                      SessionView.day => _SessionBody(
                        data: data,
                        viewToggle: viewToggle,
                      ),
                      SessionView.calendar => SessionCalendarView(
                        data: data,
                        viewToggle: viewToggle,
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

/// Today's plans when there is more than one (E8.8: an athlete's own plan alongside their group's), each by its
/// name and whose it is. Choosing one shows its session and calendar.
class _PlanPicker extends ConsumerWidget {
  const _PlanPicker({required this.current});

  final SessionDayData current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(sessionDaysProvider).value ?? const [];
    if (days.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.m, Espacio.l, 0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Wrap(
          key: const Key('session-plans'),
          spacing: Espacio.s,
          runSpacing: Espacio.s,
          children: [
            for (final d in days)
              PildoraMaktub(
                key: Key('session-plan-${d.location.assignmentId}'),
                texto: d.plan.name,
                detalle: d.ownerLabel,
                seleccionada:
                    d.location.assignmentId == current.location.assignmentId,
                onTap: () => ref
                    .read(sessionScreenProvider.notifier)
                    .selectPlan(d.location.assignmentId),
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

class _SessionBody extends ConsumerStatefulWidget {
  const _SessionBody({required this.data, required this.viewToggle});

  final SessionDayData data;

  /// Day or calendar, the first row of the header card.
  final Widget viewToggle;

  @override
  ConsumerState<_SessionBody> createState() => _SessionBodyState();
}

class _SessionBodyState extends ConsumerState<_SessionBody> {
  /// Whether the week and day pills are open. Closed, one row sums up the chosen day (Ari: compact, opened
  /// to choose or see more).
  var _picking = false;

  @override
  void initState() {
    super.initState();
    _show();
  }

  @override
  void didUpdateWidget(_SessionBody old) {
    super.didUpdateWidget(old);
    if (old.data != widget.data) _show();
  }

  /// Looks up the chosen day's session every time the view appears (E7.27), once the frame is built.
  void _show() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) ref.read(sessionScreenProvider.notifier).show(widget.data);
  });

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final state = ref.watch(sessionScreenProvider);
    final notifier = ref.read(sessionScreenProvider.notifier);
    final location = data.location;
    final plan = data.plan;
    final (:week, :day) = shownDayOf(data, state);
    final dayCount = plan.weekModelOf(week)?.days.length ?? 0;
    final planDay = planDayOf(data, week, day);
    final live = state.live;
    final dayStates = watchDayStates(ref, data);

    return ListView(
      padding: const EdgeInsets.all(Espacio.l),
      children: [
        Card(
          key: const Key('session-day-picker'),
          clipBehavior: Clip.antiAlias,
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Compact on purpose (Ari: it took too much room): view, then where we are, then who.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Espacio.s,
                  Espacio.s,
                  Espacio.xs,
                  0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: widget.viewToggle,
                      ),
                    ),
                    IconButton(
                      key: const Key('session-day-picker-toggle'),
                      tooltip: _picking ? 'Cerrar' : 'Elegir semana y día',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        _picking ? Icons.expand_less : Icons.expand_more,
                      ),
                      onPressed: () => setState(() => _picking = !_picking),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () => setState(() => _picking = !_picking),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Espacio.s,
                    vertical: Espacio.xs,
                  ),
                  child: Wrap(
                    key: const Key('session-day-summary'),
                    spacing: Espacio.xs,
                    runSpacing: Espacio.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${plan.name} · ciclo ${location.cycle} · semana ${location.week}',
                        key: const Key('session-location'),
                        style: context.textos.labelLarge,
                      ),
                      InsigniaMaktub(
                        ['S$week', ?plan.weekModelOf(week)?.name].join(' '),
                        context.colores.insigniaBase,
                      ),
                      if (dayCount > 0) ...[
                        InsigniaMaktub(
                          planDay?.name == null || planDay!.name!.isEmpty
                              ? 'Día $day'
                              : 'Día $day · ${planDay.name}',
                          context.colores.insigniaBase,
                          key: const Key('session-day-title'),
                        ),
                        isDayDone(dayStates, data, week, day)
                            ? InsigniaMaktub(
                                'Hecho',
                                context.colores.exitoContenedor,
                              )
                            : InsigniaMaktub(
                                'Pendiente',
                                context.colores.insigniaPropio,
                              ),
                      ],
                    ],
                  ),
                ),
              ),
              if (_picking)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Espacio.s),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                                onTap: () {
                                  notifier.selectDay(week, d);
                                  setState(() => _picking = false);
                                },
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              // Whose kilos show: always at hand while training.
              if (planDay != null && data.memberIds.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Espacio.s,
                    Espacio.xs,
                    Espacio.s,
                    Espacio.s,
                  ),
                  child: SessionAthleteSelector(
                    data: data,
                    selected: athleteOnScreen(data, state),
                    onSelect: notifier.selectAthlete,
                  ),
                )
              else
                const SizedBox(height: Espacio.s),
            ],
          ),
        ),
        if (planDay != null) ...[
          // The day's name is in the picker's summary (Ari: a title here repeated it).
          if (live != null && isLocalSessionId(live.session.id)) ...[
            const SizedBox(height: Espacio.s),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: InsigniaMaktub(
                'Abierta sin señal · se sube al volver la señal',
                context.colores.insigniaBase,
                key: const Key('session-opened-offline'),
                icono: Icons.cloud_off,
              ),
            ),
          ] else if (live != null &&
              (state.liveStatus == LiveStatus.connecting ||
                  state.liveStatus == LiveStatus.reconnecting)) ...[
            const SizedBox(height: Espacio.s),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: InsigniaMaktub(
                'Conectando…',
                context.colores.insigniaBase,
                key: const Key('session-live-connecting'),
                icono: Icons.sync,
              ),
            ),
          ],
          if (data.memberIds.isEmpty)
            for (final block in planDay.blocks)
              _BlockPreview(block: block, names: data.exerciseNames)
          else
            SessionLoadsView(
              data: data,
              live: live,
              week: week,
              day: day,
              planDay: planDay,
            ),
        ],
      ],
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
  return 'Atleta ${data.memberIds.indexOf(id) + 1}';
}

/// "Sin señal": says the screen shows the data saved on the device, and from when (E7.15). Nothing while reads reach
/// the server.
class LocalCopyNotice extends ConsumerWidget {
  const LocalCopyNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedAt = ref.watch(localCopyNoticeProvider);
    if (savedAt == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.m, Espacio.l, 0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: InsigniaMaktub(
          savedDataLabel(savedAt),
          context.colores.insigniaBase,
          key: const Key('local-copy-notice'),
          icono: Icons.cloud_off,
        ),
      ),
    );
  }
}

/// "Sin señal · datos guardados el 14/11 a las 09:30", in the device's time.
String savedDataLabel(DateTime savedAt) {
  final t = savedAt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return 'Sin señal · datos guardados el ${two(t.day)}/${two(t.month)} '
      'a las ${two(t.hour)}:${two(t.minute)}';
}
