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

/// The group's plan assignments: the active one with the way to end it, and the earlier ones. A new plan can
/// be assigned only while none is active. Coach only.
class AssignmentsPage extends ConsumerWidget {
  const AssignmentsPage({super.key});

  Future<void> _assign(
    BuildContext context,
    WidgetRef ref,
    AthleteGroup group,
  ) async {
    final plans = (await ref.read(plansProvider.future))
        .where((p) => p.published)
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
      today: ref.read(assignmentTodayProvider),
    );
    if (choice == null || !context.mounted) return;
    try {
      await assignPlan(
        ref,
        planId: choice.planId,
        groupId: group.id,
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
    String planName,
  ) async {
    final ok = await confirmAction(
      context,
      title: 'Terminar la asignación',
      body:
          '"$planName" deja de estar en curso para el grupo y su calendario se corta hoy. '
          'Para volver a empezarlo hay que asignarlo de nuevo.',
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
    final data = ref.watch(groupAssignmentsProvider);
    final plans = ref.watch(plansProvider).value ?? const [];
    String planName(String id) {
      for (final p in plans) {
        if (p.id == id) return p.name;
      }
      return 'Plan eliminado';
    }

    final group = data.value?.group;
    final canAssign = group != null && data.value!.active == null;
    return Scaffold(
      appBar: AppBar(title: const Text('Asignaciones')),
      floatingActionButton: canAssign
          ? FloatingActionButton(
              key: const Key('assignment-new'),
              tooltip: 'Asignar un plan',
              onPressed: () => _assign(context, ref, group),
              child: const Icon(Icons.add),
            )
          : null,
      body: asyncView(
        data,
        onRetry: () => ref.invalidate(groupAssignmentsProvider),
        builder: (data) {
          final group = data.group;
          if (group == null) {
            return const Center(
              child: Text(
                'Todavía no hay un grupo en el club.',
                key: Key('assignments-no-group'),
              ),
            );
          }
          final active = data.active;
          final earlier = [
            for (final a in data.assignments)
              if (a != active) a,
          ];
          return ListView(
            padding: const EdgeInsets.only(
              right:
                  kFloatingActionButtonMargin +
                  kMinInteractiveDimension +
                  Espacio.l,
            ),
            children: [
              SectionTitle('Grupo ${group.name}'),
              if (active == null)
                const ListTile(
                  key: Key('assignment-none-active'),
                  title: Text('No hay un plan en curso.'),
                  subtitle: Text('Asigná uno publicado con el botón +.'),
                )
              else
                ListTile(
                  key: Key('assignment-active'),
                  leading: const Icon(Icons.event_available_outlined),
                  title: Text(planName(active.planId)),
                  subtitle: Text(
                    'Activa desde el ${_formatDate(active.startDate)}',
                  ),
                  trailing: TextButton(
                    key: const Key('assignment-end'),
                    onPressed: () =>
                        _end(context, ref, active, planName(active.planId)),
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
            ],
          );
        },
      ),
    );
  }
}
