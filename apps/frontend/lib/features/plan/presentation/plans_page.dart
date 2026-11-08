import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../catalogo/presentation/catalog_admin_widgets.dart'
    show asyncView, showApiError;
import 'plan_dialogs.dart';
import 'plan_labels.dart';
import 'providers.dart';

/// The club's plans: the way into each plan's editor, and where a new one is created. Coach only.
class PlansPage extends ConsumerWidget {
  const PlansPage({super.key, required this.basePath});

  /// The route of this page; an editor lives at `<basePath>/<planId>`.
  final String basePath;

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

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Planes')),
    floatingActionButton: FloatingActionButton.extended(
      key: const Key('plan-new'),
      onPressed: () => _create(context, ref),
      icon: const Icon(Icons.add),
      label: const Text('Nuevo plan'),
    ),
    body: asyncView(
      ref.watch(plansProvider),
      onRetry: () => ref.invalidate(plansProvider),
      builder: (plans) => plans.isEmpty
          ? const Center(
              child: Text(
                'Todavía no hay planes en el club.',
                key: Key('plans-empty'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: Espacio.xxl * 2),
              children: [
                for (final p in plans)
                  ListTile(
                    key: Key('plan-${p.id}'),
                    leading: const Icon(Icons.view_week_outlined),
                    title: Text(p.name),
                    subtitle: Text(
                      '${planTypeLabel(p.type)} · ${p.modelCount == 1 ? '1 modelo' : '${p.modelCount} modelos'} · ${!p.published ? 'Borrador' : p.hasUnpublishedChanges ? 'Publicado con cambios' : 'Publicado'}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        context.go('$basePath/${Uri.encodeComponent(p.id)}'),
                  ),
              ],
            ),
    ),
  );
}
