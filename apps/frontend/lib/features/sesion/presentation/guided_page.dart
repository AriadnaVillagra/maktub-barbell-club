import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../catalogo/presentation/catalog_admin_widgets.dart'
    show confirmAction, formatKg, showApiError;
import '../../plan/presentation/plan_labels.dart' show setsSummary;
import '../domain/guided_session.dart';
import '../domain/session_repository.dart';
import '../domain/set_sync_queue.dart' show SaveState;
import '../domain/set_write.dart';
import 'guided_more_actions.dart';
import 'guided_step_view.dart';
import 'guided_summary.dart';
import 'providers.dart';
import 'session_page.dart';
import 'session_timers.dart';

/// Runs an action of the guided mode and shows the backend's error if it refuses.
Future<void> guardedGuided(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) showApiError(context, e);
  }
}

/// What ✕ leads to while the blocks go on.
enum GuidedExitChoice {
  /// "Guardar y salir": the pass goes on and this device comes back where it was.
  saveAndLeave,

  /// "Terminar el entrenamiento": the pass finishes for every device, like "Terminar el día".
  finish,
}

/// ✕ while the blocks go on (Ari, 2026-11-21): keep the pass to come back to it, or finish the training. Null is
/// "Cancelar".
Future<GuidedExitChoice?> showGuidedExit(BuildContext context) =>
    showModalBottomSheet<GuidedExitChoice>(
      context: context,
      useSafeArea: true,
      builder: (sheet) {
        ListTile option({
          required Key key,
          required IconData icon,
          required String title,
          String? subtitle,
          bool destructive = false,
          GuidedExitChoice? choice,
        }) => ListTile(
          key: key,
          minTileHeight: sheet.densidad.tactilMinimo,
          iconColor: destructive ? sheet.esquema.error : null,
          textColor: destructive ? sheet.esquema.error : null,
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          onTap: () => Navigator.pop(sheet, choice),
        );
        return Column(
          key: const Key('guided-exit-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Espacio.l,
                Espacio.l,
                Espacio.l,
                Espacio.s,
              ),
              child: Text(
                'Salir del modo guiado',
                style: sheet.textos.titleMedium,
              ),
            ),
            option(
              key: const Key('guided-exit-save'),
              icon: Icons.bookmark_outline,
              title: 'Guardar y salir',
              subtitle: 'Al volver seguís donde quedaste.',
              choice: GuidedExitChoice.saveAndLeave,
            ),
            option(
              key: const Key('guided-exit-finish'),
              icon: Icons.stop_circle_outlined,
              title: 'Terminar el entrenamiento',
              subtitle:
                  'Cierra la pasada para todos. Lo registrado queda; lo que '
                  'falta, sin hacer.',
              destructive: true,
              choice: GuidedExitChoice.finish,
            ),
            option(
              key: const Key('guided-exit-cancel'),
              icon: Icons.close,
              title: 'Cancelar',
            ),
          ],
        );
      },
    );

/// The guided mode "Entrenar" (E7.20): who trains, then each block of the day with its preview and its steps. It
/// writes the same sets as the session's list, so leaving it keeps everything finished. The pass is the session's
/// (E7.26): every device in it sees the same block and step, and entering with a pass going on resumes it.
class GuidedPage extends ConsumerStatefulWidget {
  const GuidedPage({super.key, required this.sessionPath});

  /// Where ✕ goes when there is nothing to pop back to.
  final String sessionPath;

  @override
  ConsumerState<GuidedPage> createState() => _GuidedPageState();
}

class _GuidedPageState extends ConsumerState<GuidedPage> {
  @override
  void initState() {
    super.initState();
    // The session's lookup is the day view's (E7.27). After a reload on this route that view may never show, so the
    // guided mode asks for it too once the day is known.
    ref.listenManual(sessionDayProvider, (_, next) {
      final data = next.value;
      if (data == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(sessionScreenProvider.notifier).show(data);
      });
    }, fireImmediately: true);
  }

  void _leave(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(widget.sessionPath);
    }
  }

  Future<void> _confirmLeave(BuildContext context) async {
    final ok = await confirmAction(
      context,
      title: '¿Salir del modo guiado?',
      body:
          'Lo que ya terminaron quedó registrado. La pasada sigue para los '
          'demás y al volver la retomás donde esté.',
      action: 'Salir',
    );
    if (ok && context.mounted) _leave(context);
  }

  /// ✕ while the blocks go on: keep the pass and leave, or finish it and go to the summary.
  Future<void> _exit(BuildContext context) async {
    final choice = await showGuidedExit(context);
    if (!context.mounted) return;
    switch (choice) {
      case GuidedExitChoice.saveAndLeave:
        _leave(context);
      case GuidedExitChoice.finish:
        ref.read(guidedProvider.notifier).finishDay();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final guided = ref.watch(guidedProvider);
    final day = ref.watch(sessionDayProvider);
    final data = day.value;
    final screen = ref.watch(sessionScreenProvider);
    final live = screen.live;
    // Choosing who trains needs no session (E7.27); the blocks and the summary come with the pass, which is the
    // session's. Until the day and its session were looked up, a missing one says nothing (after a reload).
    final waiting =
        (data == null && day.isLoading) ||
        (data != null && live == null && !screen.lookedUp);
    final ready =
        !waiting &&
        guided != null &&
        data != null &&
        (live != null || guided.phase == GuidedPhase.athletes);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: ready
            ? _Title(
                day: live?.session.day ?? shownDayOf(data, screen).day,
                guided: guided,
              )
            : const Text('Entrenar'),
        actions: [
          const SessionTimerButton(),
          if (ready && guided.phase == GuidedPhase.blocks) const _PassMenu(),
          IconButton(
            key: const Key('guided-exit'),
            tooltip: 'Salir del modo guiado',
            icon: const Icon(Icons.close),
            onPressed: () => switch (ready ? guided.phase : null) {
              GuidedPhase.blocks => _exit(context),
              GuidedPhase.athletes => _confirmLeave(context),
              _ => _leave(context),
            },
          ),
        ],
      ),
      body: waiting
          ? const Center(
              child: CircularProgressIndicator(key: Key('guided-loading')),
            )
          : !ready
          ? _Message(
              text: 'No hay un día del plan para entrenar.',
              onBack: () => _leave(context),
            )
          : ListView(
              padding: const EdgeInsets.all(Espacio.l),
              children: [
                switch ((guided.phase, live)) {
                  (GuidedPhase.blocks, final live?) => _Block(
                    guided: guided,
                    data: data,
                    live: live,
                    onFinish: () => _exit(context),
                  ),
                  (GuidedPhase.finished, final live?) => GuidedSummary(
                    guided: guided,
                    data: data,
                    live: live,
                    onBack: () => _leave(context),
                  ),
                  _ => _Athletes(guided: guided, data: data),
                },
              ],
            ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.day, required this.guided});

  final int day;
  final GuidedSession guided;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('Entrenando · Día $day'),
      if (guided.phase != GuidedPhase.athletes) const _SaveStatus(),
      if (guided.start != null)
        GuidedClock(
          key: const Key('guided-total-clock'),
          elapsed: guided.elapsed,
          style: context.numeros.chico,
        ),
    ],
  );
}

/// "guardando…", "✓ guardado" or "⚠ sin guardar", from the queue of what the device has to send.
class _SaveStatus extends ConsumerWidget {
  const _SaveStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(saveStateProvider);
    return Text(
      switch (state) {
        SaveState.saving => 'guardando…',
        SaveState.saved => '✓ guardado',
        SaveState.unsaved => '⚠ sin guardar',
      },
      key: const Key('guided-save-state'),
      style: context.textos.labelSmall?.copyWith(
        color: state == SaveState.unsaved ? context.esquema.error : null,
      ),
    );
  }
}

/// A time measured against the clock, refreshed every second while it is on screen.
class GuidedClock extends ConsumerStatefulWidget {
  const GuidedClock({
    super.key,
    required this.elapsed,
    this.prefix = '',
    this.style,
  });

  /// What has elapsed at a given instant; null shows nothing.
  final Duration? Function(DateTime now) elapsed;
  final String prefix;
  final TextStyle? style;

  @override
  ConsumerState<GuidedClock> createState() => _GuidedClockState();
}

class _GuidedClockState extends ConsumerState<GuidedClock> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = widget.elapsed(ref.read(guidedClockProvider)());
    if (elapsed == null) return const SizedBox.shrink();
    return Text(
      '${widget.prefix}${reloj(elapsed.inSeconds)}',
      style: widget.style,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.onBack});

  final String text;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Espacio.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: Espacio.m,
        children: [
          Text(text, style: context.textos.titleMedium),
          FilledButton(onPressed: onBack, child: const Text('Volver')),
        ],
      ),
    ),
  );
}

enum _PassAction { finishDay, startOver }

/// What can be done with the whole pass while it goes on: finish the day for everyone, or start a new pass.
class _PassMenu extends ConsumerWidget {
  const _PassMenu();

  Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    _PassAction action,
  ) async {
    final notifier = ref.read(guidedProvider.notifier);
    switch (action) {
      case _PassAction.finishDay:
        final ok = await confirmAction(
          context,
          title: '¿Terminar el día?',
          body:
              'Termina la pasada para todos los dispositivos. Lo que ya '
              'terminaron quedó registrado; lo que falta queda sin hacer.',
          action: 'Terminar',
        );
        if (ok) notifier.finishDay();
      case _PassAction.startOver:
        notifier.startOver();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      PopupMenuButton<_PassAction>(
        key: const Key('guided-pass-menu'),
        tooltip: 'Pasada',
        onSelected: (a) => _choose(context, ref, a),
        itemBuilder: (_) => const [
          PopupMenuItem(
            key: Key('guided-finish-day'),
            value: _PassAction.finishDay,
            child: Text('Terminar el día'),
          ),
          PopupMenuItem(
            key: Key('guided-start-over'),
            value: _PassAction.startOver,
            child: Text('Empezar una pasada nueva'),
          ),
        ],
      );
}

enum _BeginChoice { resume, redo }

class _Athletes extends ConsumerWidget {
  const _Athletes({required this.guided, required this.data});

  final GuidedSession guided;
  final SessionDayData data;

  /// "Comenzar". If a chosen athlete already has sets done today, asks whether to go on from what is left or to
  /// start over (E7.23).
  Future<void> _begin(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(guidedProvider.notifier);
    if (!notifier.chosenHaveRecords) return notifier.begin();
    final choice = await showDialog<_BeginChoice>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('guided-resume-dialog'),
        title: const Text('Ya hay series registradas'),
        content: const Text(
          'Alguno de los que entrenan ya tiene series hechas hoy. '
          '¿Seguís desde lo pendiente o hacés todo de nuevo? Al rehacer, '
          'cada serie que termines reemplaza la anterior.',
        ),
        actions: [
          TextButton(
            key: const Key('guided-resume-cancel'),
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          OutlinedButton(
            key: const Key('guided-redo'),
            onPressed: () => Navigator.pop(context, _BeginChoice.redo),
            child: const Text('Hacer todo de nuevo'),
          ),
          FilledButton(
            key: const Key('guided-resume'),
            onPressed: () => Navigator.pop(context, _BeginChoice.resume),
            child: const Text('Seguir desde lo pendiente'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    await notifier.begin(redo: choice == _BeginChoice.redo);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(guidedProvider.notifier);
    final opening = ref.watch(sessionScreenProvider.select((s) => s.opening));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Espacio.m,
      children: [
        Text('¿Quiénes entrenan?', style: context.textos.headlineSmall),
        Wrap(
          spacing: Espacio.s,
          runSpacing: Espacio.s,
          children: [
            for (final id in data.memberIds)
              PildoraMaktub(
                key: Key('guided-athlete-$id'),
                texto: athleteLabel(data, id),
                seleccionada: guided.athleteIds.contains(id),
                onTap: () => notifier.toggleAthlete(id),
              ),
          ],
        ),
        Wrap(
          spacing: Espacio.s,
          runSpacing: Espacio.s,
          children: [
            if (guided.canResume)
              OutlinedButton(
                key: const Key('guided-back-to-pass'),
                onPressed: notifier.resume,
                child: const Text('Volver a la pasada'),
              ),
            FilledButton(
              key: const Key('guided-begin'),
              onPressed: guided.athleteIds.isEmpty || opening
                  ? null
                  : () => guardedGuided(context, () => _begin(context, ref)),
              child: const Text('Comenzar'),
            ),
          ],
        ),
      ],
    );
  }
}

/// The block on screen: its preview, the block without steps running, or the step card.
class _Block extends ConsumerWidget {
  const _Block({
    required this.guided,
    required this.data,
    required this.live,
    required this.onFinish,
  });

  final GuidedSession guided;
  final SessionDayData data;
  final LiveSession live;

  /// Opens what ✕ opens, from the notice of a pass left open.
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = guided.run!;
    final block = guided.block!;
    final running = run.status == GuidedBlockStatus.running;
    final now = ref.read(guidedClockProvider)();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Espacio.s,
      children: [
        if (guided.isStaleAt(now))
          _StaleNotice(elapsed: guided.elapsed(now)!, onFinish: onFinish),
        Text(
          'Bloque ${guided.current + 1} de ${guided.runs.length}',
          key: const Key('guided-block-count'),
          style: context.textos.labelLarge,
        ),
        Text(
          block.name,
          key: const Key('guided-block-name'),
          style: context.textos.headlineSmall,
        ),
        if (!running)
          _Preview(guided: guided, data: data, live: live)
        else if (blockHasSteps(block))
          GuidedStepView(guided: guided, data: data, live: live)
        else
          _WholeBlock(guided: guided, data: data),
      ],
    );
  }
}

/// A pass that began hours ago and is still going on (Ari, 2026-11-21): likely one left open from before. Its times
/// are the real ones; this offers to finish it.
class _StaleNotice extends StatelessWidget {
  const _StaleNotice({required this.elapsed, required this.onFinish});

  final Duration elapsed;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final colors = context.colores.alertaContenedor;
    return SizedBox(
      width: double.infinity,
      child: Card(
        key: const Key('guided-stale'),
        margin: EdgeInsets.zero,
        color: colors.fondo,
        child: Padding(
          padding: const EdgeInsets.all(Espacio.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Espacio.s,
            children: [
              Text(
                'Esta pasada empezó hace ${elapsedLabel(elapsed)} y sigue '
                'abierta. Si quedó de antes, terminala.',
                style: context.textos.bodyMedium?.copyWith(color: colors.sobre),
              ),
              OutlinedButton(
                key: const Key('guided-stale-finish'),
                // The container's content color keeps the contrast on it.
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.sobre,
                  side: BorderSide(color: colors.sobre),
                ),
                onPressed: onFinish,
                child: const Text('Terminar el entrenamiento'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "4 h 50 min", "45 min".
String elapsedLabel(Duration elapsed) {
  final hours = elapsed.inHours;
  final minutes = elapsed.inMinutes % 60;
  if (elapsed.inDays >= 1) {
    return elapsed.inDays == 1 ? '1 día' : '${elapsed.inDays} días';
  }
  return hours == 0 ? '$minutes min' : '$hours h $minutes min';
}

/// Simultaneous or by turns, starting on the block's default.
class GuidedModePicker extends ConsumerWidget {
  const GuidedModePicker({super.key, required this.mode});

  final AthleteMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(guidedProvider.notifier);
    return Row(
      spacing: Espacio.s,
      children: [
        Text('Modo', style: context.textos.labelLarge),
        PildoraMaktub(
          key: const Key('guided-mode-simultaneous'),
          texto: 'Simultáneo',
          seleccionada: mode == AthleteMode.simultaneous,
          onTap: () => notifier.setAthleteMode(AthleteMode.simultaneous),
        ),
        PildoraMaktub(
          key: const Key('guided-mode-turns'),
          texto: 'Por turnos',
          seleccionada: mode == AthleteMode.turns,
          onTap: () => notifier.setAthleteMode(AthleteMode.turns),
        ),
      ],
    );
  }
}

/// Sequential or circuit, starting on the block's default (E7.22).
class GuidedOrderPicker extends ConsumerWidget {
  const GuidedOrderPicker({super.key, required this.mode});

  final ExecutionMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(guidedProvider.notifier);
    return Row(
      spacing: Espacio.s,
      children: [
        Text('Orden', style: context.textos.labelLarge),
        PildoraMaktub(
          key: const Key('guided-order-sequential'),
          texto: 'Secuencial',
          seleccionada: mode == ExecutionMode.sequential,
          onTap: () => notifier.setExecutionMode(ExecutionMode.sequential),
        ),
        PildoraMaktub(
          key: const Key('guided-order-circuit'),
          texto: 'Circuito',
          seleccionada: mode == ExecutionMode.circuit,
          onTap: () => notifier.setExecutionMode(ExecutionMode.circuit),
        ),
      ],
    );
  }
}

class _Preview extends ConsumerWidget {
  const _Preview({
    required this.guided,
    required this.data,
    required this.live,
  });

  final GuidedSession guided;
  final SessionDayData data;
  final LiveSession live;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(guidedProvider.notifier);
    final run = guided.run!;
    final block = guided.block!;
    final steps = blockHasSteps(block);
    final counts = setCountsOf(block, guided.athleteIds);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Espacio.s,
      children: [
        if (block.note case final note? when note.isNotEmpty)
          Text(note, style: context.textos.bodyMedium),
        for (var p = 0; p < block.prescriptions.length; p++)
          SizedBox(
            width: double.infinity,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(Espacio.m),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Espacio.xs,
                  children: [
                    Text(
                      exerciseNameOf(data, block.prescriptions[p]),
                      style: context.textos.titleSmall,
                    ),
                    if (!steps && block.prescriptions[p].sets.isNotEmpty)
                      Text(
                        setsSummary(block.prescriptions[p].sets),
                        style: context.textos.bodyMedium,
                      ),
                    if (steps)
                      for (final a in guided.athleteIds)
                        _PreviewLine(
                          key: Key('guided-preview-$p-$a'),
                          data: data,
                          live: live,
                          athleteId: a,
                          blockIndex: run.blockIndex,
                          prescriptionIndex: p,
                          prescription: block.prescriptions[p],
                          has: (counts[p][a] ?? 0) > 0,
                        ),
                  ],
                ),
              ),
            ),
          ),
        if (guided.offersAthleteMode) GuidedModePicker(mode: run.athleteMode),
        if (guided.offersExecutionMode)
          GuidedOrderPicker(mode: run.executionMode),
        const SizedBox(height: Espacio.s),
        Wrap(
          spacing: Espacio.s,
          runSpacing: Espacio.s,
          children: [
            FilledButton(
              key: const Key('guided-start-block'),
              onPressed: notifier.startBlock,
              child: const Text('Iniciar bloque'),
            ),
          ],
        ),
        GuidedMoreActionsButton(
          actions: [
            GuidedAction(
              key: const Key('guided-skip-block'),
              icon: Icons.skip_next,
              label: 'Saltar bloque',
              onTap: notifier.skipBlock,
            ),
          ],
        ),
      ],
    );
  }
}

/// One athlete's part of a prescription in the preview: the sets and the kilos they will lift.
class _PreviewLine extends ConsumerWidget {
  const _PreviewLine({
    super.key,
    required this.data,
    required this.live,
    required this.athleteId,
    required this.blockIndex,
    required this.prescriptionIndex,
    required this.prescription,
    required this.has,
  });

  final SessionDayData data;
  final LiveSession live;
  final String athleteId;
  final int blockIndex;
  final int prescriptionIndex;
  final Prescription prescription;

  /// Whether the athlete has the prescription in their day.
  final bool has;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = athleteLabel(data, athleteId);
    if (!has) {
      return Text(
        '$label: no lo tiene en su día',
        style: context.textos.bodyMedium,
      );
    }
    final adjustments = ref.watch(
      sessionScreenProvider.select((s) => s.adjustmentsOf(athleteId)),
    );
    final proposed =
        ref
            .watch(
              proposedLoadsProvider((
                clubId: data.clubId,
                sessionId: live.session.id,
                athleteId: athleteId,
                adjustments: adjustments,
              )),
            )
            .value ??
        const [];
    final kgs = <String>[];
    for (var s = 0; s < prescription.sets.length; s++) {
      final record = recordOf(
        live,
        athleteId,
        blockIndex,
        prescriptionIndex,
        s,
      );
      final kg = shownKg(
        record,
        proposed
            .where(
              (x) =>
                  x.blockIndex == blockIndex &&
                  x.prescriptionIndex == prescriptionIndex &&
                  x.setIndex == s,
            )
            .firstOrNull,
      );
      if (kg != null && !kgs.contains(formatKg(kg))) kgs.add(formatKg(kg));
    }
    return Text(
      [
        '$label: ${setsSummary(prescription.sets)}',
        if (kgs.isNotEmpty) '${kgs.join(' / ')} kg',
      ].join(' · '),
      style: context.textos.bodyMedium,
    );
  }
}

/// A block without steps, running: seen whole, with its note and, for a WoD, its timer.
class _WholeBlock extends ConsumerWidget {
  const _WholeBlock({required this.guided, required this.data});

  final GuidedSession guided;
  final SessionDayData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = guided.run!;
    final block = guided.block!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Espacio.s,
      children: [
        GuidedClock(
          key: const Key('guided-block-clock'),
          prefix: 'En curso · ',
          elapsed: (now) => now.difference(run.start!),
          style: context.numeros.chico,
        ),
        if (block.note case final note? when note.isNotEmpty)
          Text(note, style: context.textos.bodyMedium),
        if (block.categoryId == wodCategoryId ||
            block.executionMode == ExecutionMode.timed)
          SessionWodTimerButton(block: block),
        for (final p in block.prescriptions)
          Text(
            p.sets.isEmpty
                ? exerciseNameOf(data, p)
                : '${exerciseNameOf(data, p)} · ${setsSummary(p.sets)}',
            style: context.textos.bodyLarge,
          ),
        const SizedBox(height: Espacio.s),
        FilledButton(
          key: const Key('guided-finish-block'),
          onPressed: () => guardedGuided(
            context,
            ref.read(guidedProvider.notifier).finishBlock,
          ),
          child: const Text('Terminar bloque'),
        ),
      ],
    );
  }
}

/// The exercise's name, or a neutral label.
String exerciseNameOf(SessionDayData data, Prescription prescription) =>
    data.exerciseNames[prescription.exerciseId] ?? 'Ejercicio';

/// What [athleteId] recorded for that set, if anything.
SetRecord? recordOf(LiveSession live, String athleteId, int b, int p, int s) =>
    live.records
        .where(
          (r) =>
              r.athleteId == athleteId &&
              r.blockIndex == b &&
              r.prescriptionIndex == p &&
              r.setIndex == s,
        )
        .firstOrNull;
