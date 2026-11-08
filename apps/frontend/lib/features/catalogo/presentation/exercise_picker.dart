import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../domain/exercise_picker_rules.dart';
import 'providers.dart';

/// Opens the exercise picker in a modal bottom sheet. Resolves to the chosen exercise, or null when
/// the sheet is dismissed. See [ExercisePicker] for the parameters.
Future<Exercise?> showExercisePicker(
  BuildContext context, {
  String? categoryId,
  List<String> recentIds = const [],
  bool Function(Exercise)? filter,
}) => showModalBottomSheet<Exercise>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => FractionallySizedBox(
    heightFactor: 0.9,
    child: ExercisePicker(
      categoryId: categoryId,
      recentIds: recentIds,
      filter: filter,
      onSelected: (e) => Navigator.of(context).pop(e),
    ),
  ),
);

/// Searchable list of the active exercises of the active club (base and the club's own) that belong
/// to [categoryId]. Reusable: the plan editor (E5) embeds it or opens it with [showExercisePicker].
///
/// - [categoryId]: only exercises of that category; null offers every category.
/// - [recentIds]: ids of the exercises used lately, most recent first. They are listed first, in
///   that order, and the rest follow by name. What counts as "recent" is up to the caller.
/// - [filter]: when given, only the exercises it accepts are offered.
/// - [onSelected]: called with the tapped exercise.
class ExercisePicker extends ConsumerStatefulWidget {
  const ExercisePicker({
    super.key,
    this.categoryId,
    this.recentIds = const [],
    this.filter,
    required this.onSelected,
  });

  final String? categoryId;
  final List<String> recentIds;
  final bool Function(Exercise)? filter;
  final ValueChanged<Exercise> onSelected;

  @override
  ConsumerState<ExercisePicker> createState() => _ExercisePickerState();
}

class _ExercisePickerState extends ConsumerState<ExercisePicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final exercises = ref.watch(activeExercisesProvider(widget.categoryId));
    final clubId = ref.watch(catalogClubIdProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(Espacio.m),
          child: CampoBusqueda(
            hint: 'Buscar ejercicio',
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: exercises.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'No se pudo cargar el catálogo.',
                    style: context.textos.bodyLarge,
                  ),
                  const SizedBox(height: Espacio.s),
                  OutlinedButton(
                    onPressed: () => ref.invalidate(
                      activeExercisesProvider(widget.categoryId),
                    ),
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
            data: (all) {
              final shown = pickableExercises(
                widget.filter == null ? all : all.where(widget.filter!).toList(),
                clubId: clubId ?? '',
                categoryId: widget.categoryId,
                query: _query,
                recentIds: widget.recentIds,
              );
              if (shown.isEmpty) {
                return Center(
                  child: Text(
                    'No hay ejercicios que coincidan.',
                    style: context.textos.bodyLarge?.copyWith(
                      color: context.esquema.onSurfaceVariant,
                    ),
                  ),
                );
              }
              return ListView.builder(
                itemCount: shown.length,
                itemBuilder: (_, i) => ListTile(
                  title: Text(shown[i].name),
                  trailing: widget.recentIds.contains(shown[i].id)
                      ? const Icon(Icons.history)
                      : null,
                  onTap: () => widget.onSelected(shown[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Opens a searchable list of [candidates] in a bottom sheet. Resolves to the chosen one, or null.
Future<Exercise?> showExerciseSearchSheet(
  BuildContext context,
  List<Exercise> candidates,
) => showModalBottomSheet<Exercise>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => FractionallySizedBox(
    heightFactor: 0.9,
    child: _ExerciseSearchList(candidates),
  ),
);

class _ExerciseSearchList extends StatefulWidget {
  const _ExerciseSearchList(this.candidates);

  final List<Exercise> candidates;

  @override
  State<_ExerciseSearchList> createState() => _ExerciseSearchListState();
}

class _ExerciseSearchListState extends State<_ExerciseSearchList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = normalizeForSearch(_query);
    final shown = [
      for (final e in widget.candidates)
        if (q.isEmpty || normalizeForSearch(e.name).contains(q)) e,
    ]..sort((a, b) => normalizeForSearch(a.name).compareTo(normalizeForSearch(b.name)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(Espacio.m),
          child: CampoBusqueda(
            key: const Key('reference-search'),
            hint: 'Buscar ejercicio',
            autofocus: true,
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? Center(child: Text('No hay ejercicios que coincidan.', style: context.textos.bodyLarge))
              : ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (_, i) => ListTile(
                    key: ValueKey('reference-${shown[i].id}'),
                    title: Text(shown[i].name),
                    onTap: () => Navigator.of(context).pop(shown[i]),
                  ),
                ),
        ),
      ],
    );
  }
}
