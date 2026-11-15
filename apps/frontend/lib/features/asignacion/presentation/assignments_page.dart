import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../catalogo/presentation/catalog_admin_widgets.dart'
    show SectionTitle, asyncView, confirmAction, showApiError, showNotice;
import '../../plan/presentation/providers.dart' show plansProvider;
import 'assign_plan_dialog.dart';
import 'providers.dart';

String _formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _statusLabel(AssignmentStatus s) => switch (s) {
  AssignmentStatus.active => 'Activa',
  AssignmentStatus.paused => 'Pausada',
  AssignmentStatus.ended => 'Terminada',
};

/// The club's plan assignments, by owner: each group, and each athlete with a plan of their own (E8.8), with the
/// active one and the way to end it, and the earlier ones. A new plan goes to a group or an athlete that has none
/// active; an athlete's own plan lives alongside their group's. Coach only.
class AssignmentsPage extends ConsumerWidget {
  const AssignmentsPage({super.key});

  Future<void> _assign(
    BuildContext context,
    WidgetRef ref,
    List<AssignmentOwner> owners,
  ) async {
    final plans = (await ref.read(plansProvider.future))
        // A history plan records what was done; it is never assigned again.
        .where((p) => p.published && p.type != PlanType.history)
        .toList();
    if (!context.mounted) return;
    if (plans.isEmpty) {
      showNotice(
        context,
        'No hay planes publicados. Publicá un plan para poder asignarlo.',
      );
      return;
    }
    final choice = await askAssignment(
      context,
      plans: plans,
      owners: owners,
      today: ref.read(assignmentTodayProvider),
    );
    if (choice == null || !context.mounted) return;
    try {
      await assignPlan(
        ref,
        planId: choice.planId,
        owner: choice.owner,
        startDate: choice.startDate,
      );
    } catch (e) {
      if (context.mounted) showApiError(context, e);
    }
  }

  Future<void> _end(
    BuildContext context,
    WidgetRef ref,
    Assignment assignment,
    AssignmentOwner owner,
    String planName,
  ) async {
    final ok = await confirmAction(
      context,
      title: 'Terminar la asignación',
      body:
          '"$planName" deja de estar en curso para ${owner.isGroup ? 'el grupo' : owner.name} y su calendario se '
          'corta hoy. Para volver a empezarlo hay que asignarlo de nuevo.',
      action: 'Terminar',
    );
    if (!ok || !context.mounted) return;
    try {
      await endAssignment(ref, assignment.id);
    } catch (e) {
      if (context.mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(clubAssignmentsProvider);
    final plans = ref.watch(plansProvider).value ?? const [];
    String planName(String id) {
      for (final p in plans) {
        if (p.id == id) return p.name;
      }
      return 'Plan eliminado';
    }

    final free = data.value?.free ?? const <AssignmentOwner>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Asignaciones')),
      floatingActionButton: free.isNotEmpty
          ? FloatingActionButton(
              key: const Key('assignment-new'),
              tooltip: 'Asignar un plan',
              onPressed: () => _assign(context, ref, free),
              child: const Icon(Icons.add),
            )
          : null,
      body: asyncView(
        data,
        onRetry: () => ref.invalidate(clubAssignmentsProvider),
        builder: (data) {
          if (!data.hasGroup && data.assignments.isEmpty) {
            return const Center(
              child: Text(
                'Todavía no hay un grupo en el club.',
                key: Key('assignments-no-group'),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(
              right:
                  kFloatingActionButtonMargin +
                  kMinInteractiveDimension +
                  Espacio.l,
            ),
            children: [
              for (final owner in data.owners)
                // An athlete shows up once they have a plan of their own; groups always do.
                if (owner.isGroup || data.of(owner).isNotEmpty)
                  ..._ownerSection(context, ref, data, owner, planName),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _ownerSection(
    BuildContext context,
    WidgetRef ref,
    ClubAssignments data,
    AssignmentOwner owner,
    String Function(String) planName,
  ) {
    final active = data.activeOf(owner);
    final earlier = [
      for (final a in data.of(owner))
        if (a != active) a,
    ];
    return [
      SectionTitle(owner.label),
      if (active == null)
        ListTile(
          key: Key('assignment-none-active-${owner.key}'),
          title: const Text('No hay un plan en curso.'),
          subtitle: const Text('Asigná uno publicado con el botón +.'),
        )
      else
        ListTile(
          key: Key('assignment-active-${owner.key}'),
          leading: const Icon(Icons.event_available_outlined),
          title: Text(planName(active.planId)),
          subtitle: Text('Activa desde el ${_formatDate(active.startDate)}'),
          trailing: TextButton(
            key: Key('assignment-end-${owner.key}'),
            onPressed: () =>
                _end(context, ref, active, owner, planName(active.planId)),
            child: const Text('Terminar'),
          ),
        ),
      if (earlier.isNotEmpty) const SectionTitle('Anteriores'),
      for (final a in earlier)
        ListTile(
          key: Key('assignment-${a.id}'),
          leading: const Icon(Icons.history),
          title: Text(planName(a.planId)),
          subtitle: Text(
            '${_statusLabel(a.status)} · desde el ${_formatDate(a.startDate)}'
            '${a.endDate == null ? '' : ' hasta el ${_formatDate(a.endDate!)}'}',
          ),
        ),
    ];
  }
}
