import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../access/presentation/providers.dart';
import 'catalog_labels.dart';
import 'exercise_catalog_providers.dart';
import 'exercise_list_page.dart';
import 'providers.dart';

/// Exercise sheet. A base exercise is read-only and offers "create my own from this one"; the
/// club's own can be edited, archived or restored, and deleted. Athletes see no actions.
class ExerciseDetailPage extends ConsumerStatefulWidget {
  const ExerciseDetailPage({
    super.key,
    required this.basePath,
    required this.exerciseId,
  });

  final String basePath;
  final String exerciseId;

  @override
  ConsumerState<ExerciseDetailPage> createState() => _ExerciseDetailPageState();
}

class _ExerciseDetailPageState extends ConsumerState<ExerciseDetailPage> {
  bool _busy = false;

  Future<void> _run(Future<String?> Function() action) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await action();
      refreshExercises(ref);
      if (message != null) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Exercise e, String clubId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar ejercicio'),
        content: Text(
          '¿Eliminar "${e.name}"? Si ya se usa, se archiva en lugar de borrarse.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final router = GoRouter.of(context);
    var deleted = false;
    await _run(() async {
      final result = await ref
          .read(catalogRepositoryProvider)
          .deleteExercise(clubId, e.id);
      deleted = result.deleted;
      return result.deleted
          ? 'Ejercicio eliminado.'
          : 'El ejercicio está en uso: se archivó.';
    });
    if (deleted && mounted) router.go(widget.basePath);
  }

  @override
  Widget build(BuildContext context) {
    final exercises = ref.watch(catalogExercisesProvider);
    final categories =
        ref.watch(catalogCategoriesProvider).value ?? const <Category>[];
    final groups =
        ref.watch(muscleGroupsProvider).value ?? const <MuscleGroup>[];
    final patterns =
        ref.watch(movementPatternsProvider).value ?? const <MovementPattern>[];
    final canEdit = ref.watch(canPlanProvider) ?? false;
    final clubId = ref.watch(catalogClubIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ejercicio')),
      body: exercises.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(errorMessage(e))),
        data: (all) {
          final matches = all.where((x) => x.id == widget.exerciseId);
          if (matches.isEmpty || clubId == null) {
            return const Center(child: Text('No se encontró el ejercicio.'));
          }
          final e = matches.first;
          final byId = {for (final x in all) x.id: x.name};
          final t = context.textos;
          final isBase = e.scope == CatalogScope.base;
          return ListView(
            padding: const EdgeInsets.all(Espacio.l),
            children: [
              Row(
                spacing: Espacio.s,
                children: [
                  Expanded(child: Text(e.name, style: t.headlineMedium)),
                  ScopeBadge(e.scope),
                  if (!e.isActive)
                    InsigniaMaktub(
                      'Archivado',
                      context.colores.alertaContenedor,
                    ),
                ],
              ),
              const SizedBox(height: Espacio.l),
              _Field(
                'Categorías',
                [
                  for (final id in e.categoryIds)
                    ?categories.where((c) => c.id == id).firstOrNull?.name,
                ].join(', '),
              ),
              _Field('Métricas', e.metrics.map(metricLabel).join(', ')),
              if (e.defaultMetric != null)
                _Field('Métrica objetivo', metricLabel(e.defaultMetric!)),
              _Field(
                'Patrón de movimiento',
                patterns.where((p) => p.id == e.patternId).firstOrNull?.name ??
                    '',
              ),
              _Field(
                'Músculos',
                [
                  for (final m in e.muscles)
                    '${groups.where((g) => g.id == m.groupId).firstOrNull?.name ?? m.groupId} (${muscleWeightLabel(m.weight)})',
                ].join(', '),
              ),
              _Field(
                'Referencia de carga',
                e.loadReference.kind == LoadReferenceKind.otherExercise
                    ? '${referenceKindLabel(e.loadReference.kind)}: ${byId[e.loadReference.exerciseId] ?? ''}'
                    : referenceKindLabel(e.loadReference.kind),
              ),
              if (e.notes != null) _Field('Notas', e.notes!),
              const SizedBox(height: Espacio.l),
              if (canEdit && isBase)
                FilledButton.icon(
                  onPressed: () => context.go(
                    '${widget.basePath}/ejercicios/nuevo?desde=${e.id}',
                  ),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Crear uno propio a partir de este'),
                ),
              if (canEdit && !isBase) ...[
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => context.go(
                          '${widget.basePath}/ejercicios/${e.id}/editar',
                        ),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar'),
                ),
                const SizedBox(height: Espacio.s),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          final next = e.isActive
                              ? CatalogStatus.archived
                              : CatalogStatus.active;
                          await ref
                              .read(catalogRepositoryProvider)
                              .setExerciseStatus(clubId, e.id, next);
                          return e.isActive
                              ? 'Ejercicio archivado.'
                              : 'Ejercicio restaurado.';
                        }),
                  icon: Icon(
                    e.isActive
                        ? Icons.archive_outlined
                        : Icons.unarchive_outlined,
                  ),
                  label: Text(e.isActive ? 'Archivar' : 'Restaurar'),
                ),
                const SizedBox(height: Espacio.s),
                TextButton.icon(
                  onPressed: _busy ? null : () => _delete(e, clubId),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Eliminar'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Espacio.m),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.textos.labelMedium),
        Text(value.isEmpty ? '—' : value, style: context.textos.bodyLarge),
      ],
    ),
  );
}
