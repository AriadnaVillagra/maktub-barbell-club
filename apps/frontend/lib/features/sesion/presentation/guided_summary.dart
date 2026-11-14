import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../catalogo/presentation/catalog_admin_widgets.dart' show formatKg;
import '../domain/guided_session.dart';
import '../domain/plan_differences.dart';
import '../domain/session_repository.dart';
import 'guided_page.dart' show exerciseNameOf;
import 'providers.dart';
import 'session_page.dart' show athleteLabel;

/// The day's summary of the guided mode (E7.21): the time of each block, what differed from the plan, and "Guardar",
/// which waits for the queue to empty before going back to the session.
class GuidedSummary extends ConsumerStatefulWidget {
  const GuidedSummary({
    super.key,
    required this.guided,
    required this.data,
    required this.live,
    required this.onBack,
  });

  final GuidedSession guided;
  final SessionDayData data;
  final LiveSession live;
  final VoidCallback onBack;

  @override
  ConsumerState<GuidedSummary> createState() => _GuidedSummaryState();
}

class _GuidedSummaryState extends ConsumerState<GuidedSummary> {
  var _saving = false;
  var _failed = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final queue = ref.read(setSyncQueueProvider);
    await queue.flush();
    if (!mounted) return;
    if (queue.unsent.isEmpty) {
      widget.onBack();
    } else {
      setState(() {
        _saving = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final guided = widget.guided;
    final data = widget.data;
    final proposed = {
      for (final a in guided.athleteIds)
        a:
            ref
                .watch(
                  proposedLoadsProvider((
                    clubId: data.clubId,
                    sessionId: widget.live.session.id,
                    athleteId: a,
                    adjustments: ref.watch(
                      sessionScreenProvider.select((s) => s.adjustmentsOf(a)),
                    ),
                  )),
                )
                .value ??
            const <ProposedSet>[],
    };
    final differences = planDifferences(
      guided: guided,
      records: widget.live.records,
      proposed: proposed,
    );
    final run = [
      for (final r in guided.runs)
        if (r.start != null && r.end != null) r.end!.difference(r.start!),
    ];
    final inBlocks = run.fold(Duration.zero, (sum, d) => sum + d);
    final total = guided.elapsed(ref.read(guidedClockProvider)());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Espacio.m,
      children: [
        Text(
          'Día terminado',
          key: const Key('guided-finished'),
          style: context.textos.headlineSmall,
        ),
        Text('Tiempos', style: context.textos.titleMedium),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Espacio.m),
            child: Column(
              spacing: Espacio.s,
              children: [
                for (final r in guided.runs)
                  _TimeRow(
                    key: Key('guided-time-${r.blockIndex}'),
                    label: _blockLabel(guided, r),
                    value: r.start != null && r.end != null
                        ? reloj(r.end!.difference(r.start!).inSeconds)
                        : '—',
                  ),
                _TimeRow(
                  key: const Key('guided-time-blocks'),
                  label: 'Total en bloques',
                  value: reloj(inBlocks.inSeconds),
                  strong: true,
                ),
                _TimeRow(
                  key: const Key('guided-time-total'),
                  label: 'De principio a fin',
                  value: reloj((total ?? Duration.zero).inSeconds),
                ),
              ],
            ),
          ),
        ),
        Text('Diferencias con el plan', style: context.textos.titleMedium),
        if (differences.isEmpty)
          Text(
            'Se hizo todo según el plan.',
            key: const Key('guided-no-differences'),
            style: context.textos.bodyMedium,
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Espacio.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Espacio.s,
                children: [
                  for (final (i, d) in differences.indexed)
                    Text(
                      _differenceText(d),
                      key: Key('guided-difference-$i'),
                      style: context.textos.bodyMedium,
                    ),
                ],
              ),
            ),
          ),
        FilledButton(
          key: const Key('guided-save'),
          onPressed: _saving ? null : _save,
          child: Text(
            _saving
                ? 'Guardando…'
                : _failed
                ? 'Reintentar guardado'
                : 'Guardar',
          ),
        ),
      ],
    );
  }

  String _blockLabel(GuidedSession guided, GuidedBlockRun run) {
    final name = guided.day.blocks[run.blockIndex].name;
    return switch (run.status) {
      GuidedBlockStatus.skipped => '$name · salteado',
      GuidedBlockStatus.interrupted => '$name · interrumpido',
      _ => name,
    };
  }

  String _differenceText(PlanDifference d) {
    if (d.kind == PlanDifferenceKind.blockSkipped) {
      return '${d.blockName}: no se hizo';
    }
    final block = widget.guided.day.blocks[d.blockIndex!];
    final who =
        '${athleteLabel(widget.data, d.athleteId!)} · '
        '${exerciseNameOf(widget.data, block.prescriptions[d.prescriptionIndex!])}';
    return switch (d.kind) {
      PlanDifferenceKind.notDone => '$who: no lo hizo',
      PlanDifferenceKind.someSets => '$who: ${d.done} de ${d.planned} series',
      _ =>
        '$who, serie ${d.setNumber}: ${_measure(d.reps, d.kg)} '
            '(plan ${_measure(d.planReps, d.planKg)})',
    };
  }

  /// "5 × 80 kg", or "5 reps" for an exercise without kilos.
  static String _measure(int? reps, double? kg) {
    final r = reps ?? '?';
    return kg == null ? '$r reps' : '$r × ${formatKg(kg)} kg';
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    super.key,
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final style = strong
        ? context.textos.titleSmall
        : context.textos.bodyMedium;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: context.numeros.chico),
      ],
    );
  }
}
