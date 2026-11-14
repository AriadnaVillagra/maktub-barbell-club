import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../catalogo/presentation/catalog_admin_widgets.dart'
    show confirmAction, formatKg;
import '../../temporizador/presentation/widgets/iniciar_temporizador.dart';
import '../domain/guided_session.dart';
import '../domain/session_repository.dart';
import '../domain/set_write.dart';
import 'guided_page.dart';
import 'providers.dart';
import 'session_page.dart';
import 'session_set_dialogs.dart';
import 'session_timers.dart';

/// The step on screen (E7.17's list): the exercise and set, one card per athlete of the step, the rest timer and
/// what comes next.
class GuidedStepView extends ConsumerWidget {
  const GuidedStepView({
    super.key,
    required this.guided,
    required this.data,
    required this.live,
  });

  final GuidedSession guided;
  final SessionDayData data;
  final LiveSession live;

  Future<void> _interrupt(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(guidedProvider.notifier);
    final ok = await confirmAction(
      context,
      title: '¿Interrumpir el bloque?',
      body: 'Solo queda registrado lo que ya terminaron.',
      action: 'Interrumpir',
    );
    if (ok) notifier.interruptBlock();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(guidedProvider.notifier);
    final timers = SessionTimers.watch(ref);
    final run = guided.run!;
    final block = guided.block!;
    final pending = guided.pending(recordedSets(live.records));
    if (pending.isEmpty) return const SizedBox.shrink(); // the block closes
    final step = pending.first;
    final next = pending.length > 1 ? pending[1] : null;
    final nextName = next == null
        ? null
        : exerciseNameOf(data, block.prescriptions[next.prescription]);
    final prescription = block.prescriptions[step.prescription];
    final draft = guided.draftFor(step);
    final turns = run.athleteMode == AthleteMode.turns;
    final total = setCountsOf(block, guided.athleteIds)[step.prescription]
        .values
        .fold(0, (max, n) => n > max ? n : max);
    final whose = athleteLabel(data, step.athleteIds.first);
    final String main;
    if (draft.running) {
      main = turns ? 'Terminar turno' : 'Terminar serie';
    } else {
      main = turns ? 'Iniciar turno de $whose' : 'Iniciar serie';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Espacio.s,
      children: [
        GuidedClock(
          key: const Key('guided-block-clock'),
          prefix: 'Bloque en curso · ',
          elapsed: (now) => now.difference(run.start!),
          style: context.numeros.chico,
        ),
        if (guided.offersAthleteMode) GuidedModePicker(mode: run.athleteMode),
        if (guided.offersExecutionMode)
          GuidedOrderPicker(mode: run.executionMode),
        Text(
          exerciseNameOf(data, prescription),
          key: const Key('guided-exercise'),
          style: context.textos.titleLarge,
        ),
        Text(
          [
            'Serie ${step.set + 1} de $total',
            if (turns) 'turno de $whose',
            if (draft.running) 'en curso',
          ].join(' · '),
          key: const Key('guided-set'),
          style: context.textos.titleMedium,
        ),
        for (final a in step.athleteIds)
          _AthleteSetCard(
            key: Key('guided-card-$a'),
            data: data,
            live: live,
            athleteId: a,
            blockIndex: run.blockIndex,
            step: step,
            target: prescription.sets[step.set],
            draft: draft,
            redo: guided.redo,
          ),
        Wrap(
          spacing: Espacio.s,
          runSpacing: Espacio.s,
          children: [
            OutlinedButton(
              key: const Key('guided-rest'),
              onPressed: () {
                final start = timers.starterFor(block, prescription);
                if (start != null) {
                  start();
                } else {
                  pickAndStartTimer(context, ref);
                }
              },
              child: const Text('⏱ Descanso'),
            ),
            FilledButton(
              key: const Key('guided-step-main'),
              onPressed: draft.running
                  ? () => guardedGuided(context, notifier.finishStep)
                  : notifier.startStep,
              child: Text(main),
            ),
          ],
        ),
        Text(
          next == null
              ? 'Es el último paso del bloque.'
              : [
                  'Sigue: $nextName, serie ${next.set + 1}',
                  if (turns) athleteLabel(data, next.athleteIds.first),
                ].join(' · '),
          key: const Key('guided-next'),
          style: context.textos.bodyMedium,
        ),
        Wrap(
          spacing: Espacio.s,
          runSpacing: Espacio.s,
          children: [
            TextButton(
              key: const Key('guided-skip-exercise'),
              onPressed: notifier.skipExercise,
              child: const Text('Saltar este ejercicio'),
            ),
            TextButton(
              key: const Key('guided-interrupt'),
              style: TextButton.styleFrom(
                foregroundColor: context.esquema.error,
              ),
              onPressed: () => _interrupt(context, ref),
              child: const Text('Interrumpir bloque'),
            ),
          ],
        ),
      ],
    );
  }
}

/// One athlete in the step: the kilos and reps that "Terminar serie" records, editable, with the plan's percent.
class _AthleteSetCard extends ConsumerWidget {
  const _AthleteSetCard({
    super.key,
    required this.data,
    required this.live,
    required this.athleteId,
    required this.blockIndex,
    required this.step,
    required this.target,
    required this.draft,
    required this.redo,
  });

  final SessionDayData data;
  final LiveSession live;
  final String athleteId;
  final int blockIndex;
  final GuidedStep step;
  final PlanSet target;
  final GuidedStepDraft draft;

  /// The day is being redone: the card starts from the proposal and shows what was recorded before.
  final bool redo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(guidedProvider.notifier);
    final label = athleteLabel(data, athleteId);
    final adjustments = ref.watch(
      sessionScreenProvider.select((s) => s.adjustmentsOf(athleteId)),
    );
    final proposed = ref
        .watch(
          proposedLoadsProvider((
            clubId: data.clubId,
            sessionId: live.session.id,
            athleteId: athleteId,
            adjustments: adjustments,
          )),
        )
        .value
        ?.where(
          (x) =>
              x.blockIndex == blockIndex &&
              x.prescriptionIndex == step.prescription &&
              x.setIndex == step.set,
        )
        .firstOrNull;
    final before = recordOf(
      live,
      athleteId,
      blockIndex,
      step.prescription,
      step.set,
    );
    final record = redo ? null : before;
    final edit = draft.edits[athleteId];
    final kg = edit == null
        ? shownKg(record, proposed)
        : edit.manualKg ?? proposed?.kg;
    final reps = edit == null
        ? record?.reps ?? target.reps
        : edit.reps ?? target.reps;
    final pct = proposed?.appliedPct ?? record?.pctPlan;
    final notDone = draft.notDone.contains(athleteId);
    final values = [
      kg == null ? '— kg' : '${formatKg(kg)} kg',
      if (reps != null)
        '$reps reps'
      else if (target.maxReps)
        'Máx.',
    ].join(' × ');

    Future<void> editValues() async {
      final typed = await showSetValuesDialog(
        context,
        title: '$label · serie ${step.set + 1}',
        kg: kg,
        reps: reps,
      );
      if (typed == null) return;
      // Saving without touching the proposed kilos must not turn them into typed ones.
      final manual =
          typed.kg != kg ||
          (record?.manualKg ?? false) ||
          edit?.manualKg != null;
      notifier.edit(
        athleteId,
        SetEdit(manualKg: manual ? typed.kg : null, reps: typed.reps),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Espacio.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Espacio.xs,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: context.textos.titleMedium?.copyWith(
                        decoration: notDone ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  if (pct != null)
                    Text('${formatKg(pct)} %', style: context.numeros.chico),
                ],
              ),
              if (redo && before != null && before.done)
                Text(
                  [
                    'antes: ${before.reps ?? target.reps ?? '—'}',
                    if (before.kg != null) '× ${formatKg(before.kg!)} kg',
                  ].join(' '),
                  key: Key('guided-before-$athleteId'),
                  style: context.textos.bodySmall,
                ),
              if (notDone)
                Text(
                  'No hace esta serie',
                  style: context.textos.bodyMedium,
                )
              else
                TextButton(
                  key: Key('guided-edit-$athleteId'),
                  onPressed: editValues,
                  child: Text(
                    values,
                    key: Key('guided-values-$athleteId'),
                    style: context.numeros.medio,
                  ),
                ),
              Wrap(
                spacing: Espacio.s,
                runSpacing: Espacio.xs,
                children: [
                  TextButton(
                    key: Key('guided-not-done-$athleteId'),
                    onPressed: () => notifier.toggleNotDone(athleteId),
                    child: Text(
                      notDone ? 'Contar esta serie' : 'No hizo esta serie',
                    ),
                  ),
                  TextButton(
                    key: Key('guided-leave-$athleteId'),
                    onPressed: () => notifier.leaveExercise(athleteId),
                    child: const Text('Dejar el ejercicio'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
