import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../access/presentation/providers.dart';
import '../../catalogo/presentation/catalog_admin_widgets.dart' show asyncView;
import '../domain/history_labels.dart';
import 'history_page.dart' show entryBadges;
import 'providers.dart';

/// One past session as the athlete lived it: plan, day, the session's note, and each block with its exercises
/// and every set as recorded (kilos, reps, done or not, estimated) next to its target. Read-only.
class SessionHistoryPage extends ConsumerWidget {
  const SessionHistoryPage({
    super.key,
    required this.athleteId,
    required this.sessionId,
  });

  final String athleteId;
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = sessionHistoryProvider((
      athleteId: athleteId,
      sessionId: sessionId,
    ));
    final value = ref.watch(provider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          value.value == null
              ? 'Sesión'
              : historyDateLabel(value.value!.entry.date),
        ),
      ),
      body: asyncView(
        value,
        onRetry: () => ref.invalidate(provider),
        builder: (h) => ListView(
          key: const Key('session-history'),
          padding: const EdgeInsets.all(Espacio.l),
          children: [
            _Header(history: h),
            for (final block in h.blocks) ...[
              const SizedBox(height: Espacio.m),
              _BlockCard(block: block, athleteId: athleteId),
            ],
            if (h.blocks.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: Espacio.l),
                child: Text(
                  'No hay series registradas en esta sesión.',
                  key: Key('session-history-empty'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The signed-in user's own session, as the athlete of the active club.
class OwnSessionHistoryPage extends ConsumerWidget {
  const OwnSessionHistoryPage({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final athleteId = ref.watch(meProvider).value?.athleteId;
    if (athleteId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sesión')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return SessionHistoryPage(athleteId: athleteId, sessionId: sessionId);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.history});

  final SessionHistory history;

  @override
  Widget build(BuildContext context) {
    final e = history.entry;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Espacio.xs,
      children: [
        Text(
          historyPlanLabel(e),
          style: context.textos.titleLarge,
          key: const Key('session-history-plan'),
        ),
        Text(historyPositionLabel(e), style: context.textos.bodyMedium),
        Wrap(
          spacing: Espacio.xs,
          runSpacing: Espacio.xs,
          children: entryBadges(context, e),
        ),
        if (history.note case final note?)
          Padding(
            padding: const EdgeInsets.only(top: Espacio.s),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Espacio.s,
              children: [
                Icon(
                  Icons.sticky_note_2_outlined,
                  color: context.esquema.onSurfaceVariant,
                ),
                Expanded(
                  child: Text(note, key: const Key('session-history-note')),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({required this.block, required this.athleteId});

  final HistoryBlock block;
  final String athleteId;

  @override
  Widget build(BuildContext context) {
    final seconds = block.seconds;
    return Card(
      key: Key('history-block-${block.index}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Espacio.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Espacio.s,
          children: [
            Row(
              spacing: Espacio.s,
              children: [
                Expanded(
                  child: Text(
                    block.name ?? 'Bloque ${block.index + 1}',
                    style: context.textos.titleMedium,
                  ),
                ),
                if (seconds != null) ...[
                  Icon(
                    Icons.timer_outlined,
                    size: context.textos.bodyMedium!.fontSize,
                    color: context.esquema.onSurfaceVariant,
                  ),
                  Text(
                    block.interrupted
                        ? '${durationLabel(seconds)} (interrumpido)'
                        : durationLabel(seconds),
                    key: Key('history-block-time-${block.index}'),
                    style: context.numeros.chico,
                  ),
                ],
              ],
            ),
            for (final exercise in block.exercises)
              _ExerciseView(
                exercise: exercise,
                blockIndex: block.index,
                athleteId: athleteId,
              ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseView extends StatelessWidget {
  const _ExerciseView({
    required this.exercise,
    required this.blockIndex,
    required this.athleteId,
  });

  final HistoryExercise exercise;
  final int blockIndex;
  final String athleteId;

  @override
  Widget build(BuildContext context) {
    final name = exercise.exerciseName.isEmpty
        ? 'Ejercicio'
        : exercise.exerciseName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: context.textos.titleSmall),
        if (exercise.note case final note?)
          Text(
            note,
            style: context.textos.bodySmall,
            key: Key('history-note-$blockIndex-${exercise.index}'),
          ),
        for (final set in exercise.sets)
          _SetRow(
            key: Key('history-set-$blockIndex-${exercise.index}-${set.index}'),
            set: set,
            athleteId: athleteId,
          ),
      ],
    );
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({super.key, required this.set, required this.athleteId});

  final HistorySet set;
  final String athleteId;

  @override
  Widget build(BuildContext context) {
    final record = set.record;
    final muted = context.esquema.onSurfaceVariant;
    final (icon, color, status) = switch (record) {
      null => (Icons.remove, muted, 'Sin registrar'),
      SetRecord(done: true) => (
        Icons.check_circle,
        context.esquema.primary,
        'Hecha',
      ),
      SetRecord() => (Icons.cancel_outlined, muted, 'Sin hacer'),
    };
    final target = targetLabel(set.target, athleteId: athleteId);
    final result = record == null ? '' : recordLabel(record);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Espacio.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Espacio.s,
        children: [
          Semantics(
            label: status,
            child: Icon(
              icon,
              color: color,
              size: context.textos.titleMedium!.fontSize,
            ),
          ),
          SizedBox(
            width: Espacio.xl,
            child: Text(
              '${set.index + 1}',
              style: context.textos.labelMedium!.copyWith(color: muted),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.isNotEmpty ? result : status,
                  style: result.isNotEmpty
                      ? context.numeros.chico
                      : context.textos.bodyMedium!.copyWith(color: muted),
                ),
                if (target.isNotEmpty)
                  Text(
                    'Objetivo: $target',
                    style: context.textos.bodySmall!.copyWith(color: muted),
                  ),
              ],
            ),
          ),
          if (record?.estimated ?? false)
            InsigniaMaktub(
              'Estimada',
              context.colores.alertaContenedor,
              icono: Icons.auto_awesome_outlined,
            ),
        ],
      ),
    );
  }
}
