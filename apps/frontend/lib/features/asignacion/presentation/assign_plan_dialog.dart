import 'package:flutter/material.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../plan/domain/plan_repository.dart';
import 'providers.dart' show AssignmentOwner;

typedef AssignmentChoice = ({
  String planId,
  AssignmentOwner owner,
  DateTime startDate,
});

/// Asks which of the published [plans] to assign, to whom among [owners] (a group or one athlete, E8.8; the first
/// by default) and the start date (today by default).
Future<AssignmentChoice?> askAssignment(
  BuildContext context, {
  required List<PlanSummary> plans,
  required List<AssignmentOwner> owners,
  required DateTime today,
}) => showDialog<AssignmentChoice>(
  context: context,
  builder: (_) => _AssignPlanDialog(plans: plans, owners: owners, today: today),
);

class _AssignPlanDialog extends StatefulWidget {
  const _AssignPlanDialog({
    required this.plans,
    required this.owners,
    required this.today,
  });

  final List<PlanSummary> plans;
  final List<AssignmentOwner> owners;
  final DateTime today;

  @override
  State<_AssignPlanDialog> createState() => _AssignPlanDialogState();
}

class _AssignPlanDialogState extends State<_AssignPlanDialog> {
  late String _planId = widget.plans.first.id;
  late String _ownerKey = widget.owners.first.key;
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
        DropdownButtonFormField<String>(
          key: const Key('assign-owner'),
          initialValue: _ownerKey,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Para'),
          items: [
            for (final o in widget.owners)
              DropdownMenuItem(value: o.key, child: Text(o.label)),
          ],
          onChanged: (v) => setState(() => _ownerKey = v ?? _ownerKey),
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
        onPressed: () => Navigator.pop(context, (
          planId: _planId,
          owner: widget.owners.firstWhere((o) => o.key == _ownerKey),
          startDate: _date,
        )),
        child: const Text('Asignar'),
      ),
    ],
  );
}
