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
import 'prescription_dialog.dart';
import 'providers.dart';

/// Editor of a plan's structure: week models, the assignment of the 4 weeks and the days of each model.
/// Edits stay in memory until the save action in the app bar validates and sends them (E5.9); a failed
/// save leaves them as they are. Leaving with changes asks before discarding them.
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
    final saving = ref.watch(planSaveProvider(planId)).saving;
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
          actions: [
            if (value.hasValue)
              Padding(
                padding: const EdgeInsets.only(right: Espacio.s),
                child: FilledButton.icon(
                  key: const Key('plan-save'),
                  icon: saving
                      ? const SizedBox.square(
                          dimension: Espacio.l,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Guardar'),
                  onPressed: dirty && !saving
                      ? () => ref.read(planSaveProvider(planId).notifier).save()
                      : null,
                ),
              ),
          ],
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
    final save = ref.watch(planSaveProvider(planId));
    return ListView(
      padding: const EdgeInsets.all(Espacio.l),
      children: [
        if (save.problems.isNotEmpty) ...[
          ListaDeProblemas(
            key: const Key('plan-problems'),
            titulo: save.title ?? 'No se guardó el plan.',
            problemas: [
              for (final p in save.problems)
                ProblemaMaktub(p.message, ubicacion: p.location),
            ],
          ),
          const SizedBox(height: Espacio.l),
        ] else if (save.error != null) ...[
          ListaDeProblemas(
            key: const Key('plan-save-error'),
            titulo: 'No se guardó el plan.',
            problemas: [ProblemaMaktub(save.error!)],
          ),
          const SizedBox(height: Espacio.l),
        ] else if (save.justSaved && !draft.isDirty) ...[
          Text(
            'Plan guardado · id ${draft.base.id}',
            key: const Key('plan-saved'),
            style: context.textos.labelLarge,
          ),
          const SizedBox(height: Espacio.l),
        ],
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
                Flexible(
                  child: Text(
                    model.name.isEmpty ? 'Sin nombre' : model.name,
                    style: context.textos.titleSmall,
                  ),
                ),
                const SizedBox(width: Espacio.s),
                TextButton.icon(
                  key: Key('day-add-$id'),
                  icon: const Icon(Icons.add),
                  label: Text(
                    draft.canAddDay(id)
                        ? 'Agregar día'
                        : 'Máximo $maxDaysPerWeek días',
                  ),
                  onPressed: draft.canAddDay(id)
                      ? () => editor.addDay(id)
                      : null,
                ),
                const Spacer(),
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
            for (final (i, _) in model.days.indexed) ...[
              if (i > 0) const Divider(),
              _DayTile(
                key: Key('day-$id-$i'),
                modelId: id,
                index: i,
                day: model.days[i],
                draft: draft,
                editor: editor,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One day of a week model with its blocks (add, edit, remove).
class _DayTile extends ConsumerWidget {
  const _DayTile({
    super.key,
    required this.modelId,
    required this.index,
    required this.day,
    required this.draft,
    required this.editor,
  });

  final String modelId;
  final int index;
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
          trailing: IconButton(
            key: Key('day-remove-$modelId-$index'),
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Quitar día',
            onPressed: draft.canRemoveDay(modelId)
                ? () => editor.removeDay(modelId, index)
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: Espacio.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (b, block) in day.blocks.indexed) ...[
                if (b > 0) const Divider(),
                _BlockTile(
                  key: Key('block-$modelId-$index-$b'),
                  keyPrefix: '$modelId-$index',
                  index: b,
                  block: block,
                  categoryName: categoryName(block.categoryId),
                  timerName: timerName(block.timerId),
                  editor: editor,
                  modelId: modelId,
                  day: index,
                ),
              ],
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
/// A subtitle that takes no space when there is nothing to say.
Widget? _textOrNull(String text) => text.isEmpty ? null : Text(text);

class _BlockTile extends ConsumerWidget {
  const _BlockTile({
    super.key,
    required this.keyPrefix,
    required this.modelId,
    required this.day,
    required this.index,
    required this.block,
    required this.categoryName,
    required this.timerName,
    required this.editor,
  });

  final String keyPrefix;
  final String modelId;
  final int day;
  final int index;
  final PlanBlock block;
  final String? categoryName;
  final String? timerName;
  final PlanEditor editor;

  Future<void> _addExercise(BuildContext context, WidgetRef ref) async {
    final isWod = block.categoryId == wodCategoryId;
    final exercise = await showExercisePicker(
      context,
      categoryId: isWod ? null : block.categoryId,
      showCategoryFilter: isWod,
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

  Future<void> _editPrescription(
    BuildContext context,
    int p,
    Prescription prescription,
    Exercise? exercise,
  ) async {
    final edited = await askPrescription(
      context,
      initial: prescription,
      exercise: exercise,
    );
    if (edited == null) return;
    editor.updatePrescription(modelId, day, index, p, edited);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercises = ref.watch(catalogExercisesProvider).value ?? const [];
    final timers = ref.watch(clubTimersProvider).value ?? const [];
    Exercise? exerciseOf(String? id) {
      for (final e in exercises) {
        if (e.id == id) return e;
      }
      return null;
    }

    String exerciseName(String? id) =>
        exerciseOf(id)?.name ?? id ?? 'Sin ejercicio';

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
              for (final (p, prescription) in block.prescriptions.indexed) ...[
                if (p > 0) const Divider(),
                ListTile(
                  key: Key('prescription-$keyPrefix-$index-$p'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onTap: () => _editPrescription(
                    context,
                    p,
                    prescription,
                    exerciseOf(prescription.exerciseId),
                  ),
                  title: Row(
                    spacing: Espacio.l,
                    children: [
                      Flexible(
                        child: Text(exerciseName(prescription.exerciseId)),
                      ),
                      if (prescription.sets.isNotEmpty)
                        Flexible(child: Text(setsSummary(prescription.sets))),
                    ],
                  ),
                  subtitle: _textOrNull(
                    [
                      if (prescription.timerId != null)
                        'Temporizador: ${timerLabel(prescription.timerId!)}',
                      if (prescription.barKg != null)
                        'Barra: ${formatNumber(prescription.barKg!)} kg',
                      if (prescription.note != null) prescription.note!,
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
              ],
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
