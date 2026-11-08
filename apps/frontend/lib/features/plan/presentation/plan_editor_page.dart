import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../catalogo/presentation/catalog_admin_widgets.dart' show asyncView;
import '../../catalogo/presentation/exercise_picker.dart';
import '../../catalogo/presentation/catalog_admin_providers.dart';
import '../../catalogo/presentation/exercise_catalog_providers.dart';
import '../domain/plan_draft.dart';
import '../domain/prescription_defaults.dart';
import 'block_dialog.dart';
import 'plan_dialogs.dart';
import 'plan_labels.dart';
import 'providers.dart';

/// Editor of a plan's structure: week models, the assignment of the 4 weeks and the days of each model.
/// Everything is in memory; saving is E5.9. Leaving with changes asks before discarding them.
///
/// Extension points: E5.7 and E5.8 add the prescriptions and sets below the blocks in [_BlockTile], and E5.9 the save action in the app bar (it reads `PlanDraft.toPlan`).
class PlanEditorPage extends ConsumerWidget {
  const PlanEditorPage({
    super.key,
    required this.planId,
    required this.listPath,
  });

  final String planId;

  /// The plan list, where leaving the editor goes.
  final String listPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editor = planEditorProvider(planId);
    final value = ref.watch(editor);
    final dirty = value.value?.isDirty ?? false;
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirmDiscard(context) && context.mounted) {
          context.go(listPath);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(value.value?.base.name ?? 'Plan'),
          bottom: dirty
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(Espacio.xl),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: Espacio.xs),
                    child: Text(
                      'Cambios sin guardar',
                      key: const Key('plan-dirty'),
                      style: context.textos.labelMedium,
                    ),
                  ),
                )
              : null,
        ),
        body: asyncView(
          value,
          onRetry: () => ref.invalidate(editor),
          builder: (draft) => _Editor(planId: planId, draft: draft),
        ),
      ),
    );
  }
}

class _Editor extends ConsumerWidget {
  const _Editor({required this.planId, required this.draft});

  final String planId;
  final PlanDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editor = ref.read(planEditorProvider(planId).notifier);
    return ListView(
      padding: const EdgeInsets.all(Espacio.l),
      children: [
        Text(
          '${planTypeLabel(draft.base.type)} · ciclo de $planCycleWeeks semanas',
          style: context.textos.bodyLarge,
        ),
        const SizedBox(height: Espacio.l),
        Text('Asignación', style: context.textos.titleMedium),
        const SizedBox(height: Espacio.s),
        _Assignment(draft: draft, onAssign: editor.assign),
        const SizedBox(height: Espacio.xl),
        Text('Modelos de semana', style: context.textos.titleMedium),
        const SizedBox(height: Espacio.s),
        if (draft.weekModels.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Espacio.m),
            child: Text(
              'Todavía no hay modelos de semana.',
              key: Key('models-empty'),
            ),
          ),
        for (final model in draft.weekModels)
          _ModelCard(
            key: Key('model-${model.id}'),
            model: model,
            draft: draft,
            editor: editor,
          ),
        const SizedBox(height: Espacio.s),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('model-add'),
            icon: const Icon(Icons.add),
            label: const Text('Agregar modelo'),
            onPressed: () async {
              final name = await askPlanName(
                context,
                title: 'Nuevo modelo de semana',
                initial: draft.suggestedModelName,
              );
              if (name != null) editor.addModel(name);
            },
          ),
        ),
      ],
    );
  }
}

class _Assignment extends StatelessWidget {
  const _Assignment({required this.draft, required this.onAssign});

  final PlanDraft draft;
  final void Function(int week, String? modelId) onAssign;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(Espacio.m),
      child: Column(
        children: [
          for (var w = 0; w < planCycleWeeks; w++)
            Row(
              children: [
                Expanded(child: Text('Semana ${w + 1}')),
                DropdownButton<String?>(
                  key: Key('assign-$w'),
                  value: draft.assignment[w],
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Sin modelo'),
                    ),
                    for (final m in draft.weekModels)
                      DropdownMenuItem<String?>(
                        value: m.id,
                        child: Text(m.name),
                      ),
                  ],
                  onChanged: (id) => onAssign(w, id),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    super.key,
    required this.model,
    required this.draft,
    required this.editor,
  });

  final WeekModel model;
  final PlanDraft draft;
  final PlanEditor editor;

  @override
  Widget build(BuildContext context) {
    final id = model.id;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Espacio.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    model.name.isEmpty ? 'Sin nombre' : model.name,
                    style: context.textos.titleSmall,
                  ),
                ),
                IconButton(
                  key: Key('model-rename-$id'),
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Renombrar',
                  onPressed: () async {
                    final name = await askPlanName(
                      context,
                      title: 'Renombrar modelo',
                      initial: model.name,
                    );
                    if (name != null) editor.renameModel(id, name);
                  },
                ),
                IconButton(
                  key: Key('model-remove-$id'),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Quitar modelo',
                  onPressed: () => editor.removeModel(id),
                ),
              ],
            ),
            for (final (i, _) in model.days.indexed)
              _DayTile(
                key: Key('day-$id-$i'),
                modelId: id,
                index: i,
                count: model.days.length,
                day: model.days[i],
                draft: draft,
                editor: editor,
              ),
            const SizedBox(height: Espacio.xs),
            TextButton.icon(
              key: Key('day-add-$id'),
              icon: const Icon(Icons.add),
              label: Text(
                draft.canAddDay(id)
                    ? 'Agregar día'
                    : 'Máximo $maxDaysPerWeek días',
              ),
              onPressed: draft.canAddDay(id) ? () => editor.addDay(id) : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// One day of a week model with its ordered blocks (add, edit, reorder, remove).
class _DayTile extends ConsumerWidget {
  const _DayTile({
    super.key,
    required this.modelId,
    required this.index,
    required this.count,
    required this.day,
    required this.draft,
    required this.editor,
  });

  final String modelId;
  final int index;
  final int count;
  final PlanDay day;
  final PlanDraft draft;
  final PlanEditor editor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(catalogCategoriesProvider).value ?? const [];
    final timers = ref.watch(clubTimersProvider).value ?? const [];
    String? categoryName(String? id) {
      for (final c in categories) {
        if (c.id == id) return c.name;
      }
      return null;
    }

    String? timerName(String? id) {
      for (final t in timers) {
        if (t.id == id) return t.nombre;
      }
      return null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.today_outlined),
          title: Text(day.name ?? 'Día ${index + 1}'),
          subtitle: Text(
            day.blocks.length == 1
                ? '1 bloque'
                : '${day.blocks.length} bloques',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: Key('day-up-$modelId-$index'),
                icon: const Icon(Icons.arrow_upward),
                tooltip: 'Subir',
                onPressed: index == 0
                    ? null
                    : () => editor.moveDay(modelId, index, index - 1),
              ),
              IconButton(
                key: Key('day-down-$modelId-$index'),
                icon: const Icon(Icons.arrow_downward),
                tooltip: 'Bajar',
                onPressed: index == count - 1
                    ? null
                    : () => editor.moveDay(modelId, index, index + 1),
              ),
              IconButton(
                key: Key('day-remove-$modelId-$index'),
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Quitar día',
                onPressed: draft.canRemoveDay(modelId)
                    ? () => editor.removeDay(modelId, index)
                    : null,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: Espacio.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (b, block) in day.blocks.indexed)
                _BlockTile(
                  key: Key('block-$modelId-$index-$b'),
                  keyPrefix: '$modelId-$index',
                  index: b,
                  count: day.blocks.length,
                  block: block,
                  categoryName: categoryName(block.categoryId),
                  timerName: timerName(block.timerId),
                  editor: editor,
                  modelId: modelId,
                  day: index,
                ),
              TextButton.icon(
                key: Key('block-add-$modelId-$index'),
                icon: const Icon(Icons.add),
                label: const Text('Agregar bloque'),
                onPressed: () async {
                  final fields = await askBlock(context);
                  if (fields == null) return;
                  editor.addBlock(
                    modelId,
                    index,
                    PlanBlock(
                      name: fields.name,
                      categoryId: fields.categoryId,
                      timerId: fields.timerId,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One block of a day with its prescriptions (add with the category's exercise picker, remove). E5.8
/// edits their sets.
class _BlockTile extends ConsumerWidget {
  const _BlockTile({
    super.key,
    required this.keyPrefix,
    required this.modelId,
    required this.day,
    required this.index,
    required this.count,
    required this.block,
    required this.categoryName,
    required this.timerName,
    required this.editor,
  });

  final String keyPrefix;
  final String modelId;
  final int day;
  final int index;
  final int count;
  final PlanBlock block;
  final String? categoryName;
  final String? timerName;
  final PlanEditor editor;

  Future<void> _addExercise(BuildContext context, WidgetRef ref) async {
    final exercise = await showExercisePicker(
      context,
      categoryId: block.categoryId,
    );
    if (exercise == null) return;
    final timers = await ref.read(clubTimersProvider.future);
    editor.addPrescription(
      modelId,
      day,
      index,
      defaultPrescription(
        exercise,
        categoryId: block.categoryId,
        activeTimerIds: [
          for (final t in timers)
            if (t.estado == CatalogStatus.active) t.id,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercises = ref.watch(catalogExercisesProvider).value ?? const [];
    final timers = ref.watch(clubTimersProvider).value ?? const [];
    String exerciseName(String? id) {
      for (final e in exercises) {
        if (e.id == id) return e.name;
      }
      return id ?? 'Sin ejercicio';
    }

    String timerLabel(String id) {
      for (final t in timers) {
        if (t.id == id) return t.nombre;
      }
      return id;
    }

    final details = [
      categoryName ?? 'Sin categoría',
      if (block.timerId != null) 'Temporizador: ${timerName ?? block.timerId}',
    ].join(' · ');
    final tile = ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(block.name),
      subtitle: Text(details),
      onTap: () async {
        final fields = await askBlock(context, initial: block);
        if (fields == null) return;
        editor.updateBlock(
          modelId,
          day,
          index,
          (b) => PlanBlock(
            name: fields.name,
            categoryId: fields.categoryId,
            executionMode: b.executionMode,
            athleteMode: b.athleteMode,
            timerId: fields.timerId,
            prescriptions: b.prescriptions,
          ),
        );
      },
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: Key('block-up-$keyPrefix-$index'),
            icon: const Icon(Icons.arrow_upward),
            tooltip: 'Subir bloque',
            onPressed: index == 0
                ? null
                : () => editor.moveBlock(modelId, day, index, index - 1),
          ),
          IconButton(
            key: Key('block-down-$keyPrefix-$index'),
            icon: const Icon(Icons.arrow_downward),
            tooltip: 'Bajar bloque',
            onPressed: index == count - 1
                ? null
                : () => editor.moveBlock(modelId, day, index, index + 1),
          ),
          IconButton(
            key: Key('block-remove-$keyPrefix-$index'),
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Quitar bloque',
            onPressed: () => editor.removeBlock(modelId, day, index),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tile,
        Padding(
          padding: const EdgeInsets.only(left: Espacio.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (p, prescription) in block.prescriptions.indexed)
                ListTile(
                  key: Key('prescription-$keyPrefix-$index-$p'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(exerciseName(prescription.exerciseId)),
                  subtitle: Text(
                    [
                      if (prescription.sets.isNotEmpty)
                        setsSummary(prescription.sets),
                      if (prescription.timerId != null)
                        'Temporizador: ${timerLabel(prescription.timerId!)}',
                    ].join(' · '),
                  ),
                  trailing: IconButton(
                    key: Key('prescription-remove-$keyPrefix-$index-$p'),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Quitar ejercicio',
                    onPressed: () =>
                        editor.removePrescription(modelId, day, index, p),
                  ),
                ),
              TextButton.icon(
                key: Key('prescription-add-$keyPrefix-$index'),
                icon: const Icon(Icons.add),
                label: const Text('Agregar ejercicio'),
                onPressed: () => _addExercise(context, ref),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
