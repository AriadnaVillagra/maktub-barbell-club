import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../access/presentation/providers.dart';
import '../domain/exercise_list_rules.dart';
import 'catalog_admin_widgets.dart';
import 'catalog_labels.dart';
import 'category_filter_chips.dart';
import 'exercise_catalog_providers.dart';
import 'providers.dart';

/// The club's exercise catalog (default and custom), searchable and filterable by category. Club admins
/// also get the create action and can list the archived exercises. [basePath] is the catalog route in the current mode.
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
    final canEdit = ref.watch(canEditClubCatalogProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Catálogo de ejercicios')),
      floatingActionButton: canEdit
          ? FloatingActionButton(
              tooltip: 'Nuevo ejercicio',
              onPressed: () =>
                  context.go('${widget.basePath}/ejercicios/nuevo'),
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(Espacio.m),
            child: CampoBusqueda(
              hint: 'Buscar ejercicio',
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          CategoryFilterChips(
            selectedId: _categoryId,
            onChanged: (id) => setState(() => _categoryId = id),
          ),
          if (canEdit)
            SwitchListTile(
              title: const Text('Solo archivados'),
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
                  // Keeps the rows out of the add button's column, so it never covers them.
                  padding: canEdit
                      ? const EdgeInsets.only(
                          right: kFloatingActionButtonMargin +
                              kMinInteractiveDimension +
                              Espacio.l,
                        )
                      : null,
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
