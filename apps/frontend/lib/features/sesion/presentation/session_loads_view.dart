import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../catalogo/presentation/catalog_admin_widgets.dart'
    show asyncView, formatKg;
import '../domain/athlete_adjustments.dart';
import '../domain/session_repository.dart';
import 'providers.dart';
import 'session_block_card.dart';
import 'session_page.dart';

/// The open session: which present athlete is on screen, their day adjustment and the kilos of each set.
class SessionLoadsView extends ConsumerWidget {
  const SessionLoadsView({
    super.key,
    required this.data,
    required this.live,
    required this.day,
  });

  final SessionDayData data;
  final LiveSession live;
  final PlanDay day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sessionScreenProvider);
    final notifier = ref.read(sessionScreenProvider.notifier);
    final present = live.session.presentAthleteIds;
    if (present.isEmpty) return const SizedBox.shrink();
    final athleteId =
        state.athleteId ??
        (present.contains(data.ownAthleteId)
            ? data.ownAthleteId!
            : present.first);
    final adjustments = state.adjustmentsOf(athleteId);
    final loads = ref.watch(
      proposedLoadsProvider((
        clubId: data.clubId,
        sessionId: live.session.id,
        athleteId: athleteId,
        adjustments: adjustments,
      )),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Espacio.m),
        Wrap(
          spacing: Espacio.s,
          runSpacing: Espacio.s,
          children: [
            for (final id in present)
              PildoraMaktub(
                key: Key('session-athlete-$id'),
                texto: athleteLabel(data, id),
                seleccionada: id == athleteId,
                onTap: () => notifier.selectAthlete(id),
              ),
          ],
        ),
        const SizedBox(height: Espacio.m),
        _AdjustmentRow(
          keyPrefix: 'session-adjust-session',
          label: 'Ajuste del día',
          value: adjustments.session,
          onStep: (delta) => notifier.stepSessionAdjustment(athleteId, delta),
        ),
        asyncView(
          loads,
          onRetry: () => ref.invalidate(proposedLoadsProvider),
          builder: (sets) => _Blocks(
            day: day,
            names: data.exerciseNames,
            sets: {
              for (final s in sets)
                (s.blockIndex, s.prescriptionIndex, s.setIndex): s,
            },
            athleteId: athleteId,
            adjustments: adjustments,
          ),
        ),
      ],
    );
  }
}

class _Blocks extends ConsumerWidget {
  const _Blocks({
    required this.day,
    required this.names,
    required this.sets,
    required this.athleteId,
    required this.adjustments,
  });

  final PlanDay day;
  final Map<String, String> names;
  final Map<(int, int, int), ProposedSet> sets;
  final String athleteId;
  final AthleteAdjustments adjustments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(sessionScreenProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var b = 0; b < day.blocks.length; b++)
          SessionBlockCard(
            key: Key('session-block-$b'),
            block: day.blocks[b],
            children: [
              for (var p = 0; p < day.blocks[b].prescriptions.length; p++)
                if (day.blocks[b].prescriptions[p].exerciseId
                    case final exerciseId?) ...[
                  if (p > 0) const Divider(),
                  Text(
                    names[exerciseId] ?? 'Ejercicio',
                    style: context.textos.titleSmall,
                  ),
                  if (blockTakesAdjustment(day.blocks[b]))
                    _AdjustmentRow(
                      keyPrefix: 'session-adjust-ex-$b-$p',
                      label: 'Ajuste del ejercicio',
                      value: adjustments.effectiveFor(exerciseId),
                      onStep: (delta) => notifier.stepExerciseAdjustment(
                        athleteId,
                        exerciseId,
                        delta,
                      ),
                    ),
                  for (
                    var s = 0;
                    s < day.blocks[b].prescriptions[p].sets.length;
                    s++
                  )
                    _SetRow(
                      index: s,
                      target: day.blocks[b].prescriptions[p].sets[s],
                      proposed: sets[(b, p, s)],
                      keyId: '$b-$p-$s',
                    ),
                ],
            ],
          ),
      ],
    );
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.index,
    required this.target,
    required this.proposed,
    required this.keyId,
  });

  final int index;
  final PlanSet target;
  final ProposedSet? proposed;
  final String keyId;

  @override
  Widget build(BuildContext context) {
    final kg = proposed?.kg;
    final factor = proposed?.workFactor;
    final detail = [
      if (target.maxReps)
        'Máx.'
      else if (target.reps != null)
        '${target.reps} reps',
      if (proposed?.appliedPct != null) '${formatKg(proposed!.appliedPct!)} %',
      if (factor != null) 'factor ${formatKg(factor)} %',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Espacio.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Serie ${index + 1}', style: context.textos.labelLarge),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    key: Key('session-detail-$keyId'),
                    style: context.textos.bodySmall,
                  ),
              ],
            ),
          ),
          Text(
            kg == null ? '—' : '${formatKg(kg)} kg',
            key: Key('session-kg-$keyId'),
            style: context.numeros.medio,
          ),
        ],
      ),
    );
  }
}

class _AdjustmentRow extends StatelessWidget {
  const _AdjustmentRow({
    required this.keyPrefix,
    required this.label,
    required this.value,
    required this.onStep,
  });

  final String keyPrefix;
  final String label;
  final int value;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label, style: context.textos.labelLarge)),
      IconButton(
        key: Key('$keyPrefix-minus'),
        icon: const Icon(Icons.remove),
        tooltip: 'Bajar el ajuste',
        onPressed: () => onStep(-Ajuste.paso),
      ),
      Text(
        '$value %',
        key: Key('$keyPrefix-value'),
        style: context.numeros.chico,
      ),
      IconButton(
        key: Key('$keyPrefix-plus'),
        icon: const Icon(Icons.add),
        tooltip: 'Subir el ajuste',
        onPressed: () => onStep(Ajuste.paso),
      ),
      TextButton(
        key: Key('$keyPrefix-reset'),
        onPressed: () => onStep(0),
        child: const Text('Quitar'),
      ),
    ],
  );
}
