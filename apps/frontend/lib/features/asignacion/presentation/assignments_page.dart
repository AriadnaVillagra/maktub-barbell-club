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

/// The club's plan assignments (E6.7): the ones in course, each with who does it and the way to change that or to end
/// it, and the ended ones. A plan goes to a list of athletes; an athlete can be in several at once. Coach only.
class AssignmentsPage extends ConsumerWidget {
  const AssignmentsPage({super.key});

  Future<void> _assign(
    BuildContext context,
    WidgetRef ref,
    List<ClubAthlete> athletes,
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
      athletes: athletes,
      today: ref.read(assignmentTodayProvider),
    );
    if (choice == null || !context.mounted) return;
    try {
      await assignPlan(
        ref,
        planId: choice.planId,
        athleteIds: choice.athleteIds,
        startDate: choice.startDate,
      );
    } catch (e) {
      if (context.mounted) showApiError(context, e);
    }
  }

  Future<void> _changeAthletes(
    BuildContext context,
    WidgetRef ref,
    ClubAssignments data,
    Assignment assignment,
    String planName,
  ) async {
    final chosen = await askAssignmentAthletes(
      context,
      planName: planName,
      athletes: data.athletes,
      current: assignment.currentAthleteIds,
    );
    if (chosen == null || !context.mounted) return;
    try {
      await setAssignmentAthletes(ref, assignment.id, chosen);
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
          '"$planName" deja de estar en curso para todos sus atletas y su calendario se corta hoy. '
          'Para sacar solo a alguien, usá Atletas. Para volver a empezarlo hay que asignarlo de nuevo.',
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

    final athletes = data.value?.athletes ?? const <ClubAthlete>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Asignaciones')),
      floatingActionButton: athletes.isNotEmpty
          ? FloatingActionButton(
              key: const Key('assignment-new'),
              tooltip: 'Asignar un plan',
              onPressed: () => _assign(context, ref, athletes),
              child: const Icon(Icons.add),
            )
          : null,
      body: asyncView(
        data,
        onRetry: () => ref.invalidate(clubAssignmentsProvider),
        builder: (data) {
          if (data.athletes.isEmpty && data.assignments.isEmpty) {
            return const Center(
              child: Text(
                'Todavía no hay atletas en el club.',
                key: Key('assignments-no-athletes'),
              ),
            );
          }
          final active = data.active;
          final ended = data.ended;
          return ListView(
            padding: const EdgeInsets.only(
              right:
                  kFloatingActionButtonMargin +
                  kMinInteractiveDimension +
                  Espacio.l,
            ),
            children: [
              const SectionTitle('En curso'),
              if (active.isEmpty)
                const ListTile(
                  key: Key('assignment-none-active'),
                  title: Text('No hay planes en curso.'),
                  subtitle: Text('Asigná uno publicado con el botón +.'),
                ),
              for (final a in active)
                _ActiveTile(
                  assignment: a,
                  planName: planName(a.planId),
                  names: data.namesOf(a.currentAthleteIds),
                  onAthletes: () => _changeAthletes(
                    context,
                    ref,
                    data,
                    a,
                    planName(a.planId),
                  ),
                  onEnd: () => _end(context, ref, a, planName(a.planId)),
                ),
              if (ended.isNotEmpty) const SectionTitle('Terminadas'),
              for (final a in ended)
                ListTile(
                  key: Key('assignment-${a.id}'),
                  leading: const Icon(Icons.history),
                  title: Text(planName(a.planId)),
                  subtitle: Text(
                    '${data.namesOf(a.athleteIds)} · desde el ${_formatDate(a.startDate)}'
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

class _ActiveTile extends StatelessWidget {
  const _ActiveTile({
    required this.assignment,
    required this.planName,
    required this.names,
    required this.onAthletes,
    required this.onEnd,
  });

  final Assignment assignment;
  final String planName;
  final String names;
  final VoidCallback onAthletes;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final id = assignment.id;
    final paused = assignment.status == AssignmentStatus.paused
        ? '${_statusLabel(AssignmentStatus.paused)} · '
        : '';
    return ListTile(
      key: Key('assignment-active-$id'),
      leading: const Icon(Icons.event_available_outlined),
      title: Text(planName),
      subtitle: Text(
        '$paused${names.isEmpty ? 'Sin atletas' : names}\n'
        'Desde el ${_formatDate(assignment.startDate)}',
      ),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        key: Key('assignment-menu-$id'),
        tooltip: 'Opciones',
        onSelected: (v) => v == 'athletes' ? onAthletes() : onEnd(),
        itemBuilder: (_) => [
          PopupMenuItem(
            key: Key('assignment-athletes-$id'),
            value: 'athletes',
            child: const Text('Atletas'),
          ),
          PopupMenuItem(
            key: Key('assignment-end-$id'),
            value: 'end',
            child: const Text('Terminar'),
          ),
        ],
      ),
    );
  }
}
