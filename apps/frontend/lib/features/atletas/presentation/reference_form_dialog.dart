import 'package:flutter/material.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../../core/red/cliente_api.dart';
import '../../catalogo/presentation/exercise_picker.dart';
import '../domain/reference_form_rules.dart';
import 'athlete_sheet_widgets.dart' show formatDate;

/// Saves what the form collected. [date] is null for the fixed weight. Throws `ErrorDeApi` to
/// show the backend's message inside the form.
typedef SaveReference = Future<void> Function(
  Exercise exercise,
  double value,
  DateTime? date,
);

/// Opens the form for [kind]. Resolves to true when something was saved.
Future<bool> showReferenceForm(
  BuildContext context, {
  required ReferenceKind kind,
  required DateTime today,
  required SaveReference onSave,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) =>
          ReferenceFormDialog(kind: kind, today: today, onSave: onSave),
    ) ??
    false;

/// Form to record an RM, a work factor or a fixed weight: exercise, value and (except for the fixed
/// weight) a date that starts at today and can be changed.
class ReferenceFormDialog extends StatefulWidget {
  const ReferenceFormDialog({
    super.key,
    required this.kind,
    required this.today,
    required this.onSave,
  });

  final ReferenceKind kind;
  final DateTime today;
  final SaveReference onSave;

  @override
  State<ReferenceFormDialog> createState() => _ReferenceFormDialogState();
}

class _ReferenceFormDialogState extends State<ReferenceFormDialog> {
  final _value = TextEditingController();
  Exercise? _exercise;
  late DateTime _date = widget.today;
  String? _error;
  bool _saving = false;

  bool get _hasDate => widget.kind != ReferenceKind.fixedWeight;

  String get _title => switch (widget.kind) {
    ReferenceKind.rm => 'Cargar RM',
    ReferenceKind.factor => 'Cargar factor de trabajo',
    ReferenceKind.fixedWeight => 'Fijar kilaje',
  };

  String get _valueLabel => widget.kind == ReferenceKind.factor ? '%' : 'kg';

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Future<void> _pickExercise() async {
    final chosen = await showExercisePicker(
      context,
      filter: (e) => acceptsReference(widget.kind, e),
    );
    if (chosen != null) setState(() => _exercise = chosen);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(widget.today.year + 1, 12, 31),
    );
    if (picked != null) setState(() => _date = soloFecha(picked));
  }

  Future<void> _save() async {
    final exercise = _exercise;
    final value = parsePositive(_value.text);
    if (exercise == null) {
      setState(() => _error = 'Elegí un ejercicio.');
      return;
    }
    if (value == null) {
      setState(() => _error = 'Ingresá un valor mayor que cero.');
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      await widget.onSave(exercise, value, _hasDate ? _date : null);
      if (mounted) Navigator.of(context).pop(true);
    } on ErrorDeApi catch (e) {
      if (mounted) {
        setState(() {
          _error = e.mensaje;
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Espacio.m,
        children: [
          OutlinedButton(
            key: const Key('form-exercise'),
            onPressed: _saving ? null : _pickExercise,
            child: Text(_exercise?.name ?? 'Elegir ejercicio'),
          ),
          TextField(
            key: const Key('form-value'),
            controller: _value,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Valor ($_valueLabel)'),
          ),
          if (_hasDate)
            OutlinedButton.icon(
              key: const Key('form-date'),
              onPressed: _saving ? null : _pickDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text('Desde ${formatDate(_date)}'),
            ),
          if (_error != null)
            Text(
              _error!,
              key: const Key('form-error'),
              style: context.textos.bodyMedium?.copyWith(
                color: context.esquema.error,
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('form-save'),
        onPressed: _saving ? null : _save,
        child: const Text('Guardar'),
      ),
    ],
  );
}
