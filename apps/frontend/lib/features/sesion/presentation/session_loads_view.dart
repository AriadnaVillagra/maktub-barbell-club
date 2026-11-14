import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../catalogo/presentation/catalog_admin_widgets.dart'
    show asyncView, formatKg, showApiError;
import '../domain/athlete_adjustments.dart';
import '../domain/session_repository.dart';
import '../domain/set_write.dart';
import 'providers.dart';
import 'session_block_card.dart';
import 'session_page.dart';
import 'session_set_dialogs.dart';
import 'session_timers.dart';

/// Runs a write and shows the backend's error if it refuses.
Future<void> _guarded(
  BuildContext context,
  Future<void> Function() write,
) async {
  try {
    await write();
  } catch (e) {
    if (context.mounted) showApiError(context, e);
  }
}

/// The open session: which present athlete is on screen, their day adjustment and each set to mark and edit.
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
            records: {
              for (final r in live.records)
                if (r.athleteId == athleteId)
                  (r.blockIndex, r.prescriptionIndex, r.setIndex): r,
            },
            clubId: data.clubId,
            athleteId: athleteId,
            adjustments: adjustments,
          ),
        ),
        const SizedBox(height: Espacio.m),
        _NoteRow(
          keyPrefix: 'session-note-day',
          title: 'Nota de la sesión',
          note: live.session.note,
          onSave: (note) => notifier.saveSessionNote(data.clubId, note),
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
    required this.records,
    required this.clubId,
    required this.athleteId,
    required this.adjustments,
  });

  final PlanDay day;
  final Map<String, String> names;
  final Map<(int, int, int), ProposedSet> sets;

  /// What the athlete on screen recorded, by position.
  final Map<(int, int, int), SetRecord> records;
  final String clubId;
  final String athleteId;
  final AthleteAdjustments adjustments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(sessionScreenProvider.notifier);
    final timers = SessionTimers.watch(ref);
    SetWrite writeOf(int b, int p, int s, String exerciseId) => SetWrite.of(
      records[(b, p, s)],
      athleteId: athleteId,
      blockIndex: b,
      prescriptionIndex: p,
      setIndex: s,
      adjustment: adjustments.effectiveFor(exerciseId),
    );

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
                      record: records[(b, p, s)],
                      keyId: '$b-$p-$s',
                      onToggle: () async {
                        final start = records[(b, p, s)]?.done ?? false
                            ? null
                            : timers.starterFor(
                                day.blocks[b],
                                day.blocks[b].prescriptions[p],
                              );
                        await notifier.writeSet(
                          clubId,
                          writeOf(b, p, s, exerciseId).toggled(),
                        );
                        start?.call();
                      },
                      onEdit: (kg, reps) => notifier.writeSet(
                        clubId,
                        writeOf(
                          b,
                          p,
                          s,
                          exerciseId,
                        ).edited(manualKg: kg, reps: reps),
                      ),
                    ),
                  if (day.blocks[b].prescriptions[p].sets.isNotEmpty)
                    _NoteRow(
                      keyPrefix: 'session-note-$b-$p',
                      title: 'Nota del ejercicio',
                      note: records[(b, p, 0)]?.note,
                      onSave: (note) => notifier.writeSet(
                        clubId,
                        writeOf(b, p, 0, exerciseId).withNote(note),
                      ),
                    ),
                  if (_editedSets(b, p, day.blocks[b].prescriptions[p])
                      case final edited when edited.isNotEmpty)
                    TextButton(
                      key: Key('session-restore-$b-$p'),
                      onPressed: () => _guarded(context, () async {
                        for (final s in edited) {
                          await notifier.writeSet(
                            clubId,
                            writeOf(b, p, s, exerciseId).restored(),
                          );
                        }
                      }),
                      child: const Text('Volver a lo planificado'),
                    ),
                ],
            ],
          ),
      ],
    );
  }

  /// The indexes of the sets of that prescription the athlete changed away from the plan.
  List<int> _editedSets(int b, int p, Prescription prescription) => [
    for (var s = 0; s < prescription.sets.length; s++)
      if (records[(b, p, s)] case final record? when setIsEdited(record)) s,
  ];
}

class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.index,
    required this.target,
    required this.proposed,
    required this.record,
    required this.keyId,
    required this.onToggle,
    required this.onEdit,
  });

  final int index;
  final PlanSet target;
  final ProposedSet? proposed;
  final SetRecord? record;
  final String keyId;
  final Future<void> Function() onToggle;

  /// A null [kg] lets the server compute them; a null [reps] takes the plan's.
  final Future<void> Function(double? kg, int? reps) onEdit;

  Future<void> _edit(BuildContext context, double? kg, int? reps) async {
    final values = await showSetValuesDialog(
      context,
      title: 'Serie ${index + 1}',
      kg: kg,
      reps: reps,
    );
    if (values == null || !context.mounted) return;
    // Saving without touching the proposed kilos must not turn them into typed ones.
    final typed = values.kg != kg || (record?.manualKg ?? false);
    await _guarded(
      context,
      () => onEdit(typed ? values.kg : null, values.reps),
    );
  }

  @override
  Widget build(BuildContext context) {
    final kg = shownKg(record, proposed);
    final reps = record?.reps ?? target.reps;
    final done = record?.done ?? false;
    final factor = proposed?.workFactor;
    final fromRecord = record != null && (record!.manualKg || done);
    final pct = fromRecord ? record!.pctPlan : proposed?.appliedPct;
    final detail = [
      if (record?.reps != null)
        '${record!.reps} reps'
      else if (target.maxReps)
        'Máx.'
      else if (target.reps != null)
        '${target.reps} reps',
      if (pct != null) '${formatKg(pct)} %',
      if (factor != null) 'factor ${formatKg(factor)} %',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Espacio.xs),
      child: Row(
        children: [
          IconButton(
            key: Key('session-check-$keyId'),
            icon: Icon(
              done ? Icons.check_circle : Icons.radio_button_unchecked,
              color: done ? context.esquema.primary : null,
            ),
            tooltip: done ? 'Desmarcar la serie' : 'Marcar la serie',
            onPressed: () => _guarded(context, onToggle),
          ),
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
          TextButton(
            key: Key('session-edit-$keyId'),
            onPressed: () => _edit(context, kg, reps),
            child: Text(
              kg == null ? '—' : '${formatKg(kg)} kg',
              key: Key('session-kg-$keyId'),
              style: context.numeros.medio,
            ),
          ),
        ],
      ),
    );
  }
}

/// A free note: what it says, and a button to write or change it.
class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.keyPrefix,
    required this.title,
    required this.note,
    required this.onSave,
  });

  final String keyPrefix;
  final String title;
  final String? note;
  final Future<void> Function(String note) onSave;

  Future<void> _write(BuildContext context) async {
    final written = await showNoteDialog(context, title: title, note: note);
    if (written == null || written == (note ?? '') || !context.mounted) return;
    await _guarded(context, () => onSave(written));
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (note case final text?)
        Text(
          text,
          key: Key('$keyPrefix-text'),
          style: context.textos.bodyMedium,
        ),
      TextButton(
        key: Key('$keyPrefix-edit'),
        onPressed: () => _write(context),
        child: Text(note == null ? 'Agregar nota' : 'Editar nota'),
      ),
    ],
  );
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
