import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../catalogo/presentation/catalog_admin_providers.dart';
import '../domain/prescription_edit.dart';
import 'plan_labels.dart';

/// Edits a prescription: its sets one by one (reps always; `%` if the exercise is loaded by % of RM; kg
/// if it has a fixed load), the note, its own timer and the bar override. Returns the edited prescription,
/// or null if cancelled. Nothing is validated here (E5.9 does it when saving).
Future<Prescription?> askPrescription(
  BuildContext context, {
  required Prescription initial,
  required Exercise? exercise,
}) => showDialog<Prescription>(
  context: context,
  builder: (_) => _PrescriptionDialog(initial: initial, exercise: exercise),
);

final _decimalText = RegExp(r'^\d*[.,]?\d*$');

/// Keeps only digits.
final _wholeFormatter = FilteringTextInputFormatter.digitsOnly;

/// Keeps digits and one decimal separator (comma or point).
final _decimalFormatter = TextInputFormatter.withFunction(
  (old, value) => _decimalText.hasMatch(value.text) ? value : old,
);

class _PrescriptionDialog extends ConsumerStatefulWidget {
  const _PrescriptionDialog({required this.initial, required this.exercise});

  final Prescription initial;
  final Exercise? exercise;

  @override
  ConsumerState<_PrescriptionDialog> createState() =>
      _PrescriptionDialogState();
}

class _PrescriptionDialogState extends ConsumerState<_PrescriptionDialog> {
  late List<PlanSet> _sets = widget.initial.sets.isEmpty
      ? const [PlanSet()]
      : widget.initial.sets;
  late String _note = widget.initial.note ?? '';
  late String? _timerId = widget.initial.timerId;
  late String _bar = widget.initial.barKg == null
      ? ''
      : formatNumber(widget.initial.barKg!);

  /// Changes whenever rows are added or removed, so the fields are rebuilt with the new initial texts.
  int _generation = 0;

  bool get _hasPct =>
      widget.exercise?.metrics.contains(Metric.loadPctRm) ??
      _sets.any((s) => s.pct != null);
  bool get _hasKg =>
      widget.exercise?.metrics.contains(Metric.fixedLoad) ??
      _sets.any((s) => s.kg != null);

  void _changeSet(
    int i, {
    int? Function(PlanSet)? reps,
    double? Function(PlanSet)? pct,
    double? Function(PlanSet)? kg,
  }) {
    final s = _sets[i];
    _sets = [
      for (final (j, x) in _sets.indexed)
        j == i
            ? setWith(
                s,
                reps: reps == null ? s.reps : reps(s),
                pct: pct == null ? s.pct : pct(s),
                kg: kg == null ? s.kg : kg(s),
              )
            : x,
    ];
  }

  void _submit() => Navigator.pop(
    context,
    prescriptionWith(
      widget.initial,
      sets: _sets,
      note: _note,
      timerId: _timerId,
      barKg: parseTypedNumber(_bar),
    ),
  );

  Widget _numberField({
    required Key key,
    required String label,
    required String initial,
    required List<TextInputFormatter> formatters,
    required ValueChanged<String> onChanged,
  }) => Expanded(
    child: TextFormField(
      key: key,
      initialValue: initial,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: formatters,
      decoration: InputDecoration(labelText: label),
      onChanged: onChanged,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final timers = ref.watch(clubTimersProvider).value ?? const [];
    final timerItems = [
      for (final t in timers)
        if (t.estado == CatalogStatus.active || t.id == _timerId) t,
    ];
    final exerciseBar = widget.exercise?.barKg;
    return AlertDialog(
      title: Text(widget.exercise?.name ?? 'Ejercicio'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, set) in _sets.indexed)
                Row(
                  key: Key('set-row-$i'),
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: Espacio.xl,
                      child: Text('${i + 1}', style: context.textos.labelLarge),
                    ),
                    _numberField(
                      key: ValueKey('set-reps-$i-$_generation'),
                      label: 'Reps',
                      initial: set.reps?.toString() ?? '',
                      formatters: [_wholeFormatter],
                      onChanged: (t) =>
                          _changeSet(i, reps: (_) => parseTypedReps(t)),
                    ),
                    if (_hasPct) ...[
                      const SizedBox(width: Espacio.s),
                      _numberField(
                        key: ValueKey('set-pct-$i-$_generation'),
                        label: '%',
                        initial: set.pct == null ? '' : formatNumber(set.pct!),
                        formatters: [_decimalFormatter],
                        onChanged: (t) =>
                            _changeSet(i, pct: (_) => parseTypedNumber(t)),
                      ),
                    ],
                    if (_hasKg) ...[
                      const SizedBox(width: Espacio.s),
                      _numberField(
                        key: ValueKey('set-kg-$i-$_generation'),
                        label: 'kg',
                        initial: set.kg == null ? '' : formatNumber(set.kg!),
                        formatters: [_decimalFormatter],
                        onChanged: (t) =>
                            _changeSet(i, kg: (_) => parseTypedNumber(t)),
                      ),
                    ],
                    IconButton(
                      key: Key('set-remove-$i'),
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Quitar serie',
                      onPressed: _sets.length <= 1
                          ? null
                          : () => setState(() {
                              _sets = removeSet(_sets, i);
                              _generation++;
                            }),
                    ),
                  ],
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('set-add'),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar serie'),
                  onPressed: () => setState(() {
                    _sets = addSet(_sets);
                    _generation++;
                  }),
                ),
              ),
              const SizedBox(height: Espacio.s),
              TextFormField(
                key: const Key('prescription-note-field'),
                initialValue: _note,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Nota'),
                onChanged: (t) => _note = t,
              ),
              const SizedBox(height: Espacio.l),
              DropdownButtonFormField<String?>(
                key: const Key('prescription-timer-field'),
                initialValue: timerItems.any((t) => t.id == _timerId)
                    ? _timerId
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Temporizador'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('El del bloque'),
                  ),
                  for (final t in timerItems)
                    DropdownMenuItem<String?>(
                      value: t.id,
                      child: Text(t.nombre),
                    ),
                ],
                onChanged: (id) => setState(() => _timerId = id),
              ),
              const SizedBox(height: Espacio.l),
              TextFormField(
                key: const Key('prescription-bar-field'),
                initialValue: _bar,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [_decimalFormatter],
                decoration: InputDecoration(
                  labelText: 'Barra (kg)',
                  helperText: switch (exerciseBar) {
                    null => 'Vacío: la del ejercicio',
                    noBarKg => 'Vacío: el ejercicio va sin barra',
                    final kg => 'Vacío: la del ejercicio (${formatNumber(kg)} kg)',
                  },
                ),
                onChanged: (t) => _bar = t,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('prescription-ok'),
          onPressed: _submit,
          child: const Text('Aceptar'),
        ),
      ],
    );
  }
}
