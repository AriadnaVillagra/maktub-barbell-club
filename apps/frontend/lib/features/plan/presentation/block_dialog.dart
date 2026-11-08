import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../catalogo/presentation/catalog_admin_providers.dart';
import '../../catalogo/presentation/exercise_catalog_providers.dart';

/// The fields a coach chooses for a block. Execution and athlete mode keep the model's defaults
/// (sequential, simultaneous): M1 runs nothing else.
typedef BlockFields = ({
  String name,
  String categoryId,
  String? timerId,
  String? note,
});

/// Asks for the name, category, timer (any type: a WoD block needs EMOM, tabata...) and note of a block,
/// starting from [initial] when editing. A blank note comes back as null.
/// Null if cancelled.
Future<BlockFields?> askBlock(BuildContext context, {PlanBlock? initial}) =>
    showDialog<BlockFields>(
      context: context,
      builder: (_) => _BlockDialog(initial: initial),
    );

class _BlockDialog extends ConsumerStatefulWidget {
  const _BlockDialog({this.initial});

  final PlanBlock? initial;

  @override
  ConsumerState<_BlockDialog> createState() => _BlockDialogState();
}

class _BlockDialogState extends ConsumerState<_BlockDialog> {
  late final _controller = TextEditingController(text: widget.initial?.name);
  late String? _categoryId = widget.initial?.categoryId;
  late String? _timerId = widget.initial?.timerId;
  late final _note = TextEditingController(text: widget.initial?.note);

  @override
  void dispose() {
    _controller.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _valid => _controller.text.trim().isNotEmpty && _categoryId != null;

  void _submit() {
    if (!_valid) return;
    Navigator.pop(context, (
      name: _controller.text.trim(),
      categoryId: _categoryId!,
      timerId: _timerId,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(catalogCategoriesProvider).value ?? const [];
    final timers = ref.watch(clubTimersProvider).value ?? const [];
    // Active ones, plus the current choice even if it was archived since.
    final categoryItems = [
      for (final c in categories)
        if (c.status == CatalogStatus.active || c.id == _categoryId) c,
    ];
    final timerItems = [
      for (final t in timers)
        if (t.estado == CatalogStatus.active || t.id == _timerId) t,
    ];
    return AlertDialog(
      title: Text(widget.initial == null ? 'Nuevo bloque' : 'Editar bloque'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('block-name-field'),
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nombre'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: Espacio.l),
            DropdownButtonFormField<String>(
              key: const Key('block-category-field'),
              initialValue: categoryItems.any((c) => c.id == _categoryId)
                  ? _categoryId
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Categoría'),
              items: [
                for (final c in categoryItems)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (id) => setState(() => _categoryId = id),
            ),
            const SizedBox(height: Espacio.l),
            DropdownButtonFormField<String?>(
              key: const Key('block-timer-field'),
              initialValue: timerItems.any((t) => t.id == _timerId)
                  ? _timerId
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Temporizador',
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Ninguno'),
                ),
                for (final t in timerItems)
                  DropdownMenuItem<String?>(value: t.id, child: Text(t.nombre)),
              ],
              onChanged: (id) => setState(() => _timerId = id),
            ),
            const SizedBox(height: Espacio.l),
            TextField(
              key: const Key('block-note-field'),
              controller: _note,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Nota'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('block-ok'),
          onPressed: _valid ? _submit : null,
          child: const Text('Aceptar'),
        ),
      ],
    );
  }
}
