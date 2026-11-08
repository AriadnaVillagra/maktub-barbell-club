import 'package:flutter/material.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../plan/domain/plan_repository.dart';

typedef AssignmentChoice = ({String planId, DateTime startDate});

/// Asks which of the published [plans] to assign and the start date (today by default).
Future<AssignmentChoice?> askAssignment(
  BuildContext context, {
  required List<PlanSummary> plans,
  required DateTime today,
}) => showDialog<AssignmentChoice>(
  context: context,
  builder: (_) => _AssignPlanDialog(plans: plans, today: today),
);

class _AssignPlanDialog extends StatefulWidget {
  const _AssignPlanDialog({required this.plans, required this.today});

  final List<PlanSummary> plans;
  final DateTime today;

  @override
  State<_AssignPlanDialog> createState() => _AssignPlanDialogState();
}

class _AssignPlanDialogState extends State<_AssignPlanDialog> {
  late String _planId = widget.plans.first.id;
  late DateTime _date = widget.today;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(widget.today.year - 1),
      lastDate: DateTime(widget.today.year + 2, 12, 31),
    );
    if (picked != null) setState(() => _date = soloFecha(picked));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Asignar un plan'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: const Key('assign-plan'),
          initialValue: _planId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Plan'),
          items: [
            for (final p in widget.plans)
              DropdownMenuItem(value: p.id, child: Text(p.name)),
          ],
          onChanged: (v) => setState(() => _planId = v ?? _planId),
        ),
        const SizedBox(height: Espacio.m),
        OutlinedButton.icon(
          key: const Key('assign-date'),
          onPressed: _pickDate,
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text('Inicio: ${aIsoFecha(_date)}'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('assign-confirm'),
        onPressed: () =>
            Navigator.pop(context, (planId: _planId, startDate: _date)),
        child: const Text('Asignar'),
      ),
    ],
  );
}
