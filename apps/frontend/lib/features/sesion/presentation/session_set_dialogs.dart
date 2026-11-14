import 'package:flutter/material.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../catalogo/presentation/catalog_admin_widgets.dart' show formatKg;

/// The kilos and reps typed for a set. Null is an empty field: back to what the plan proposes.
typedef SetValues = ({double? kg, int? reps});

/// Asks for a set's kilos and reps. Null when cancelled.
Future<SetValues?> showSetValuesDialog(
  BuildContext context, {
  required String title,
  required double? kg,
  required int? reps,
}) => showDialog<SetValues>(
  context: context,
  builder: (_) => _SetValuesDialog(title: title, kg: kg, reps: reps),
);

class _SetValuesDialog extends StatefulWidget {
  const _SetValuesDialog({required this.title, this.kg, this.reps});

  final String title;
  final double? kg;
  final int? reps;

  @override
  State<_SetValuesDialog> createState() => _SetValuesDialogState();
}

class _SetValuesDialogState extends State<_SetValuesDialog> {
  late final _kg = TextEditingController(
    text: widget.kg == null ? '' : formatKg(widget.kg!),
  );
  late final _reps = TextEditingController(text: widget.reps?.toString() ?? '');
  String? _error;

  @override
  void dispose() {
    _kg.dispose();
    _reps.dispose();
    super.dispose();
  }

  void _save() {
    final kgText = _kg.text.trim().replaceAll(',', '.');
    final repsText = _reps.text.trim();
    final kg = kgText.isEmpty ? null : double.tryParse(kgText);
    final reps = repsText.isEmpty ? null : int.tryParse(repsText);
    if ((kgText.isNotEmpty && (kg == null || kg < 0)) ||
        (repsText.isNotEmpty && (reps == null || reps < 0))) {
      setState(() => _error = 'Revisá los valores.');
      return;
    }
    Navigator.of(context).pop((kg: kg, reps: reps));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Espacio.m,
      children: [
        TextField(
          key: const Key('session-set-kg'),
          controller: _kg,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Kilos'),
        ),
        TextField(
          key: const Key('session-set-reps'),
          controller: _reps,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Reps'),
        ),
        if (_error != null)
          Text(
            _error!,
            key: const Key('session-set-error'),
            style: context.textos.bodyMedium?.copyWith(
              color: context.esquema.error,
            ),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('session-set-save'),
        onPressed: _save,
        child: const Text('Guardar'),
      ),
    ],
  );
}

/// Asks for a free note. Null when cancelled; empty clears the note.
Future<String?> showNoteDialog(
  BuildContext context, {
  required String title,
  required String? note,
}) => showDialog<String>(
  context: context,
  builder: (_) => _NoteDialog(title: title, note: note),
);

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.title, this.note});

  final String title;
  final String? note;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _note = TextEditingController(text: widget.note ?? '');

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: const Key('session-note-field'),
      controller: _note,
      maxLines: 4,
      minLines: 2,
      maxLength: maxNoteLength,
      decoration: const InputDecoration(labelText: 'Nota'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('session-note-save'),
        onPressed: () => Navigator.of(context).pop(_note.text.trim()),
        child: const Text('Guardar'),
      ),
    ],
  );
}
