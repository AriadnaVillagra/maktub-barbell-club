import 'package:flutter/material.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import 'plan_labels.dart';

/// Asks for a non-empty name. Null if cancelled.
Future<String?> askPlanName(
  BuildContext context, {
  required String title,
  String initial = '',
}) => showDialog<String>(
  context: context,
  builder: (_) => _NameDialog(title: title, initial: initial),
);

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: const Key('plan-name-field'),
      controller: _controller,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Nombre'),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('plan-name-ok'),
        onPressed: _submit,
        child: const Text('Aceptar'),
      ),
    ],
  );
}

/// Asks for the name and type of a new plan. Null if cancelled.
Future<({String name, PlanType type})?> askNewPlan(BuildContext context) =>
    showDialog<({String name, PlanType type})>(
      context: context,
      builder: (_) => const _NewPlanDialog(),
    );

class _NewPlanDialog extends StatefulWidget {
  const _NewPlanDialog();

  @override
  State<_NewPlanDialog> createState() => _NewPlanDialogState();
}

class _NewPlanDialogState extends State<_NewPlanDialog> {
  final _controller = TextEditingController();
  PlanType _type = PlanType.regular;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, (name: name, type: _type));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nuevo plan'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('plan-name-field'),
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre'),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: Espacio.l),
        SegmentedButton<PlanType>(
          key: const Key('plan-type'),
          segments: [
            for (final t in PlanType.values)
              ButtonSegment(
                value: t,
                label: Text(planTypeLabel(t), key: Key('plan-type-${t.cable}')),
              ),
          ],
          selected: {_type},
          onSelectionChanged: (s) => setState(() => _type = s.first),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('plan-create-ok'),
        onPressed: _submit,
        child: const Text('Crear'),
      ),
    ],
  );
}

/// Whether to leave the editor and drop the unsaved changes.
Future<bool> confirmDiscard(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Descartar cambios'),
        content: const Text(
          'Los cambios no se guardaron todavía y se van a perder.',
        ),
        actions: [
          TextButton(
            key: const Key('plan-keep-editing'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Seguir editando'),
          ),
          FilledButton(
            key: const Key('plan-discard'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    ) ??
    false;
