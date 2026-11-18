import 'package:flutter/material.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../plan/domain/plan_repository.dart';
import 'providers.dart' show ClubAthlete;

typedef AssignmentChoice = ({
  String planId,
  List<String> athleteIds,
  DateTime startDate,
});

/// Asks which of the published [plans] to assign, to which of the club's [athletes] (all chosen at first; at least
/// one) and the start date (today by default). E6.7: a plan is for a list of athletes, not a group.
Future<AssignmentChoice?> askAssignment(
  BuildContext context, {
  required List<PlanSummary> plans,
  required List<ClubAthlete> athletes,
  required DateTime today,
}) => showDialog<AssignmentChoice>(
  context: context,
  builder: (_) =>
      _AssignPlanDialog(plans: plans, athletes: athletes, today: today),
);

/// Asks who does [planName] from today on, among the club's [athletes], with [current] chosen at first. Null when
/// cancelled. At least one stays chosen: to leave nobody, the assignment is ended instead.
Future<List<String>?> askAssignmentAthletes(
  BuildContext context, {
  required String planName,
  required List<ClubAthlete> athletes,
  required List<String> current,
}) => showDialog<List<String>>(
  context: context,
  builder: (_) => _AthletesDialog(
    planName: planName,
    athletes: athletes,
    current: current,
  ),
);

class _AssignPlanDialog extends StatefulWidget {
  const _AssignPlanDialog({
    required this.plans,
    required this.athletes,
    required this.today,
  });

  final List<PlanSummary> plans;
  final List<ClubAthlete> athletes;
  final DateTime today;

  @override
  State<_AssignPlanDialog> createState() => _AssignPlanDialogState();
}

class _AssignPlanDialogState extends State<_AssignPlanDialog> {
  late String _planId = widget.plans.first.id;
  late final Set<String> _chosen = {for (final a in widget.athletes) a.id};
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
    content: SingleChildScrollView(
      child: Column(
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
          Text('Para', style: context.textos.labelLarge),
          const SizedBox(height: Espacio.xs),
          _AthleteChips(
            athletes: widget.athletes,
            chosen: _chosen,
            onChanged: () => setState(() {}),
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
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('assign-confirm'),
        onPressed: _chosen.isEmpty
            ? null
            : () => Navigator.pop(context, (
                planId: _planId,
                athleteIds: [
                  for (final a in widget.athletes)
                    if (_chosen.contains(a.id)) a.id,
                ],
                startDate: _date,
              )),
        child: const Text('Asignar'),
      ),
    ],
  );
}

class _AthletesDialog extends StatefulWidget {
  const _AthletesDialog({
    required this.planName,
    required this.athletes,
    required this.current,
  });

  final String planName;
  final List<ClubAthlete> athletes;
  final List<String> current;

  @override
  State<_AthletesDialog> createState() => _AthletesDialogState();
}

class _AthletesDialogState extends State<_AthletesDialog> {
  late final Set<String> _chosen = {...widget.current};

  // An athlete who is in the plan but no longer in the club still shows, so removing them is possible.
  late final List<ClubAthlete> _options = [
    ...widget.athletes,
    for (final id in widget.current)
      if (!widget.athletes.any((a) => a.id == id)) (id: id, name: 'Atleta'),
  ];

  bool get _changed =>
      _chosen.length != widget.current.length ||
      !_chosen.containsAll(widget.current);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Atletas de "${widget.planName}"'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Desde hoy. Quien sale conserva los días que hizo; quien entra empieza hoy, '
            'en la semana en que va el plan.',
          ),
          const SizedBox(height: Espacio.m),
          _AthleteChips(
            athletes: _options,
            chosen: _chosen,
            onChanged: () => setState(() {}),
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
        key: const Key('assignment-athletes-confirm'),
        onPressed: _chosen.isEmpty || !_changed
            ? null
            : () => Navigator.pop(context, [
                for (final a in _options)
                  if (_chosen.contains(a.id)) a.id,
              ]),
        child: const Text('Guardar'),
      ),
    ],
  );
}

/// One chip per athlete; [chosen] is changed in place and [onChanged] called.
class _AthleteChips extends StatelessWidget {
  const _AthleteChips({
    required this.athletes,
    required this.chosen,
    required this.onChanged,
  });

  final List<ClubAthlete> athletes;
  final Set<String> chosen;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: Espacio.s,
    runSpacing: Espacio.s,
    children: [
      for (final a in athletes)
        FilterChip(
          key: Key('assign-athlete-${a.id}'),
          label: Text(a.name),
          selected: chosen.contains(a.id),
          onSelected: (on) {
            on ? chosen.add(a.id) : chosen.remove(a.id);
            onChanged();
          },
        ),
    ],
  );
}
