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
}) => showModalBottomSheet<Exercise>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => FractionallySizedBox(
    heightFactor: 0.9,
    child: ExercisePicker(
      categoryId: categoryId,
      recentIds: recentIds,
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
/// - [onSelected]: called with the tapped exercise.
class ExercisePicker extends ConsumerStatefulWidget {
  const ExercisePicker({
    super.key,
    this.categoryId,
    this.recentIds = const [],
    required this.onSelected,
  });

  final String? categoryId;
  final List<String> recentIds;
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
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar ejercicio',
            ),
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
                all,
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
