import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_core/maktub_core.dart' show PlanType;
import 'package:maktub_ui/maktub_ui.dart';

import '../../asignacion/presentation/assign_plan_dialog.dart';
import '../../asignacion/presentation/providers.dart'
    show
        assignPlan,
        assignmentTodayProvider,
        fetchGroupAssignments,
        groupAssignmentsProvider;
import '../../catalogo/presentation/catalog_admin_widgets.dart'
    show asyncView, showApiError, showNotice;
import '../domain/plan_filter.dart';
import '../domain/plan_repository.dart';
import 'plan_dialogs.dart';
import 'plan_labels.dart';
import 'providers.dart';

/// The club's plans: the way into each plan's editor, and where a new one is created. Coach only.
/// The list is split into active and past plans ([isPastPlan]).
class PlansPage extends ConsumerStatefulWidget {
  const PlansPage({super.key, required this.basePath});

  /// The route of this page; an editor lives at `<basePath>/<planId>`.
  final String basePath;

  @override
  ConsumerState<PlansPage> createState() => _PlansPageState();
}

class _PlansPageState extends ConsumerState<PlansPage> {
  bool _showPast = false;

  String get basePath => widget.basePath;

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final data = await askNewPlan(context);
    if (data == null || !context.mounted) return;
    try {
      final plan = await createPlan(ref, name: data.name, type: data.type);
      if (plan != null && context.mounted) {
        context.go('$basePath/${Uri.encodeComponent(plan.id)}');
      }
    } catch (e) {
      if (context.mounted) showApiError(context, e);
    }
  }

  /// Quick way to assign [plan] to the club's group, without going through Asignaciones.
  Future<void> _assign(
    BuildContext context,
    WidgetRef ref,
    PlanSummary plan,
  ) async {
    try {
      final data = await fetchGroupAssignments(ref);
      if (!context.mounted) return;
      final group = data.group;
      if (group == null) {
        showNotice(context, 'Todavía no hay un grupo en el club.');
        return;
      }
      if (data.active != null) {
        showNotice(
          context,
          'El grupo ya tiene un plan en curso. Terminalo en Asignaciones para asignar otro.',
        );
        return;
      }
      final choice = await askAssignment(
        context,
        plans: [plan],
        today: ref.read(assignmentTodayProvider),
      );
      if (choice == null || !context.mounted) return;
      await assignPlan(
        ref,
        planId: choice.planId,
        groupId: group.id,
        startDate: choice.startDate,
      );
      if (context.mounted) {
        showNotice(context, '"${plan.name}" asignado a ${group.name}.');
      }
    } catch (e) {
      if (context.mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Until the assignments load, every non-history plan counts as active.
    final assignments =
        ref.watch(groupAssignmentsProvider).value?.assignments ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Planes')),
      floatingActionButton: FloatingActionButton(
        key: const Key('plan-new'),
        tooltip: 'Nuevo plan',
        onPressed: () => _create(context, ref),
        child: const Icon(Icons.add),
      ),
      body: asyncView(
        ref.watch(plansProvider),
        onRetry: () => ref.invalidate(plansProvider),
        builder: (allPlans) {
          final plans = [
            for (final p in allPlans)
              if (isPastPlan(p, assignments) == _showPast) p,
          ];
          final filter = SegmentedButton<bool>(
            key: const Key('plans-filter'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Activos')),
              ButtonSegment(value: true, label: Text('Pasados')),
            ],
            selected: {_showPast},
            onSelectionChanged: (s) => setState(() => _showPast = s.first),
          );
          return allPlans.isEmpty
              ? const Center(
                  child: Text(
                    'Todavía no hay planes en el club.',
                    key: Key('plans-empty'),
                  ),
                )
              : ListView(
                  // Keeps the cards out of the add button's column, so it never covers them.
                  padding: const EdgeInsets.fromLTRB(
                    Espacio.m,
                    Espacio.m,
                    kFloatingActionButtonMargin +
                        kMinInteractiveDimension +
                        Espacio.l,
                    Espacio.m,
                  ),
                  children: [
                    filter,
                    const SizedBox(height: Espacio.m),
                    if (plans.isEmpty)
                      Text(
                        _showPast
                            ? 'No hay planes pasados.'
                            : 'No hay planes activos.',
                        key: const Key('plans-filter-empty'),
                      ),
                    for (final p in plans)
                      Card(
                        child: ListTile(
                          key: Key('plan-${p.id}'),
                          leading: const Icon(Icons.view_week_outlined),
                          title: Text(p.name),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: Espacio.xs),
                            child: Wrap(
                              spacing: Espacio.xs,
                              runSpacing: Espacio.xs,
                              children: [
                                InsigniaMaktub(
                                  planTypeLabel(p.type),
                                  context.colores.insigniaBase,
                                ),
                                InsigniaMaktub(
                                  p.modelCount == 1
                                      ? '1 modelo'
                                      : '${p.modelCount} modelos',
                                  context.colores.insigniaBase,
                                ),
                                switch ((
                                  p.published,
                                  p.hasUnpublishedChanges,
                                )) {
                                  (false, _) => InsigniaMaktub(
                                    'Borrador',
                                    context.colores.insigniaPropio,
                                  ),
                                  (true, true) => InsigniaMaktub(
                                    'Publicado con cambios',
                                    context.colores.alertaContenedor,
                                  ),
                                  (true, false) => InsigniaMaktub(
                                    'Publicado',
                                    context.colores.exitoContenedor,
                                  ),
                                },
                              ],
                            ),
                          ),
                          // A history plan records what was done; it is never assigned again.
                          trailing: p.type == PlanType.history
                              ? null
                              : FilledButton.tonal(
                                  key: Key('plan-assign-${p.id}'),
                                  onPressed: p.published
                                      ? () => _assign(context, ref, p)
                                      : null,
                                  child: const Text('Asignar'),
                                ),
                          onTap: () => context.go(
                            '$basePath/${Uri.encodeComponent(p.id)}',
                          ),
                        ),
                      ),
                  ],
                );
        },
      ),
    );
  }
}
