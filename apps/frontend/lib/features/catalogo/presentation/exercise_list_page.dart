import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../access/presentation/providers.dart';
import '../domain/exercise_list_rules.dart';
import 'catalog_labels.dart';
import 'exercise_catalog_providers.dart';
import 'providers.dart';

/// The club's exercise catalog (base and own), searchable and filterable by category. Coaches also get
/// the create action and can show archived exercises. [basePath] is the catalog route in the current mode.
class ExerciseListPage extends ConsumerStatefulWidget {
  const ExerciseListPage({super.key, required this.basePath});

  final String basePath;

  @override
  ConsumerState<ExerciseListPage> createState() => _ExerciseListPageState();
}

class _ExerciseListPageState extends ConsumerState<ExerciseListPage> {
  String _query = '';
  String? _categoryId;
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final exercises = ref.watch(catalogExercisesProvider);
    final categories =
        ref.watch(catalogCategoriesProvider).value ?? const <Category>[];
    final clubId = ref.watch(catalogClubIdProvider);
    final canEdit = ref.watch(canPlanProvider) ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Catálogo de ejercicios')),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () =>
                  context.go('${widget.basePath}/ejercicios/nuevo'),
              icon: const Icon(Icons.add),
              label: const Text('Nuevo ejercicio'),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(Espacio.m),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar ejercicio',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Espacio.m),
            child: Row(
              spacing: Espacio.s,
              children: [
                ChoiceChip(
                  label: const Text('Todas'),
                  selected: _categoryId == null,
                  onSelected: (_) => setState(() => _categoryId = null),
                ),
                for (final c in categories.where(
                  (c) => c.status == CatalogStatus.active,
                ))
                  ChoiceChip(
                    label: Text(c.name),
                    selected: _categoryId == c.id,
                    onSelected: (_) => setState(() => _categoryId = c.id),
                  ),
              ],
            ),
          ),
          if (canEdit)
            SwitchListTile(
              title: const Text('Mostrar archivados'),
              value: _showArchived,
              onChanged: (v) => setState(() => _showArchived = v),
            ),
          Expanded(
            child: exercises.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(errorMessage(e), style: context.textos.bodyLarge),
                    TextButton(
                      onPressed: () => ref.invalidate(catalogExercisesProvider),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
              data: (all) {
                final shown = listedExercises(
                  all,
                  clubId: clubId ?? '',
                  categoryId: _categoryId,
                  query: _query,
                  showArchived: canEdit && _showArchived,
                );
                if (shown.isEmpty) {
                  return Center(
                    child: Text(
                      'No hay ejercicios.',
                      style: context.textos.bodyLarge,
                    ),
                  );
                }
                final names = {for (final c in categories) c.id: c.name};
                return ListView(
                  children: [
                    for (final e in shown)
                      ListTile(
                        key: ValueKey('exercise-${e.id}'),
                        title: Text(e.name),
                        subtitle: Text(
                          [for (final id in e.categoryIds) ?names[id]]
                              .join(' · '),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          spacing: Espacio.s,
                          children: [
                            if (!e.isActive)
                              InsigniaMaktub(
                                'Archivado',
                                context.colores.alertaContenedor,
                              ),
                            ScopeBadge(e.scope),
                          ],
                        ),
                        onTap: () =>
                            context.go('${widget.basePath}/ejercicios/${e.id}'),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// "Base" or "Propio", so the origin of an entry is clear at a glance.
class ScopeBadge extends StatelessWidget {
  const ScopeBadge(this.scope, {super.key});

  final CatalogScope scope;

  @override
  Widget build(BuildContext context) => scope == CatalogScope.base
      ? InsigniaMaktub('Base', context.colores.insigniaBase)
      : InsigniaMaktub('Propio', context.colores.insigniaPropio);
}
