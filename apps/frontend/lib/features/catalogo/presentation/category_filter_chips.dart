import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import 'exercise_catalog_providers.dart';

/// Chips that wrap onto new lines to narrow a list of exercises to one active category of the club.
/// [selectedId] null means "Todas".
class CategoryFilterChips extends ConsumerWidget {
  const CategoryFilterChips({
    super.key,
    required this.selectedId,
    required this.onChanged,
  });

  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories =
        ref.watch(catalogCategoriesProvider).value ?? const <Category>[];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Espacio.m),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          spacing: Espacio.s,
          runSpacing: Espacio.s,
          children: [
            ChoiceChip(
              key: const Key('category-chip-all'),
              label: const Text('Todas'),
              selected: selectedId == null,
              onSelected: (_) => onChanged(null),
            ),
            for (final c in categories.where(
              (c) => c.status == CatalogStatus.active,
            ))
              ChoiceChip(
                key: Key('category-chip-${c.id}'),
                label: Text(c.name),
                selected: selectedId == c.id,
                onSelected: (_) => onChanged(c.id),
              ),
          ],
        ),
      ),
    );
  }
}
