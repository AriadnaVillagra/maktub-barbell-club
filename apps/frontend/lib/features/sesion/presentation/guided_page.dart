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

/// The guided mode "Entrenar" (E7.20): who trains, then each block of the day with its preview and its steps. It
/// writes the same sets as the session's list, so leaving it keeps everything finished.
class GuidedPage extends ConsumerWidget {
  const GuidedPage({super.key, required this.sessionPath});

  /// Where ✕ goes when there is nothing to pop back to.
  final String sessionPath;

  void _leave(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(sessionPath);
    }
  }

  Future<void> _confirmLeave(BuildContext context) async {
    final ok = await confirmAction(
      context,
      title: '¿Salir del modo guiado?',
      body: 'Lo que ya terminaron quedó registrado.',
      action: 'Salir',
    );
    if (ok && context.mounted) _leave(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guided = ref.watch(guidedProvider);
    final data = ref.watch(sessionDayProvider).value;
    final live = ref.watch(sessionScreenProvider.select((s) => s.live));
    final ready = guided != null && data != null && live != null;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: ready
            ? _Title(day: live.session.day, guided: guided)
            : const Text('Entrenar'),
        actions: [
          const SessionTimerButton(),
          IconButton(
            key: const Key('guided-exit'),
            tooltip: 'Salir del modo guiado',
            icon: const Icon(Icons.close),
            onPressed: () => ready && guided.phase != GuidedPhase.finished
                ? _confirmLeave(context)
                : _leave(context),
          ),
        ],
      ),
      body: !ready
          ? _Message(
              text: 'Abrí la sesión del día para entrenar.',
              onBack: () => _leave(context),
            )
          : ListView(
              padding: const EdgeInsets.all(Espacio.l),
              children: [
                switch (guided.phase) {
                  GuidedPhase.athletes => _Athletes(guided: guided, data: data),
                  GuidedPhase.blocks => _Block(
                    guided: guided,
                    data: data,
                    live: live,
                  ),
                  GuidedPhase.finished => GuidedSummary(
                    guided: guided,
                    data: data,
                    live: live,
                    onBack: () => _leave(context),
                  ),
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

class _Athletes extends ConsumerWidget {
  const _Athletes({required this.guided, required this.data});

  final GuidedSession guided;
  final SessionDayData data;

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
            for (final id in data.group.memberIds)
              PildoraMaktub(
                key: Key('guided-athlete-$id'),
                texto: athleteLabel(data, id),
                seleccionada: guided.athleteIds.contains(id),
                onTap: () => notifier.toggleAthlete(id),
              ),
          ],
        ),
        FilledButton(
          key: const Key('guided-begin'),
          onPressed: guided.athleteIds.isEmpty || opening
              ? null
              : () => guardedGuided(context, notifier.begin),
          child: const Text('Comenzar'),
        ),
      ],
    );
  }
}

/// The block on screen: its preview, the block without steps running, or the step card.
class _Block extends ConsumerWidget {
  const _Block({required this.guided, required this.data, required this.live});

  final GuidedSession guided;
  final SessionDayData data;
  final LiveSession live;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = guided.run!;
    final block = guided.block!;
    final running = run.status == GuidedBlockStatus.running;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Espacio.s,
      children: [
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
        const SizedBox(height: Espacio.s),
        Wrap(
          spacing: Espacio.s,
          runSpacing: Espacio.s,
          children: [
            OutlinedButton(
              key: const Key('guided-skip-block'),
              onPressed: notifier.skipBlock,
              child: const Text('Saltar bloque'),
            ),
            FilledButton(
              key: const Key('guided-start-block'),
              onPressed: notifier.startBlock,
              child: const Text('Iniciar bloque'),
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
