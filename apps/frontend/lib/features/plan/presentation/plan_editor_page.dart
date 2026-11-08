import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../catalogo/presentation/catalog_admin_widgets.dart' show asyncView;
import '../domain/plan_draft.dart';
import 'plan_dialogs.dart';
import 'plan_labels.dart';
import 'providers.dart';

/// Editor of a plan's structure: week models, the assignment of the 4 weeks and the days of each model.
/// Everything is in memory; saving is E5.9. Leaving with changes asks before discarding them.
///
/// Extension points: E5.6 adds the blocks inside [_DayTile], E5.7 and E5.8 the prescriptions and sets
/// below them, and E5.9 the save action in the app bar (it reads `PlanDraft.toPlan`).
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

/// One day of a week model. Blocks (E5.6) will render as its children.
class _DayTile extends StatelessWidget {
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
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.today_outlined),
    title: Text(day.name ?? 'Día ${index + 1}'),
    subtitle: Text(
      day.blocks.length == 1 ? '1 bloque' : '${day.blocks.length} bloques',
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
  );
}
