import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../access/presentation/providers.dart';
import '../domain/catalog_admin_repository.dart';
import 'catalog_admin_providers.dart';
import 'catalog_admin_widgets.dart';
import 'providers.dart';

/// The club's categories: base ones are listed fixed; coaches create, rename, archive and delete the
/// club's own. Anyone else only reads (F2 §5, §6).
class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit = ref.watch(canPlanProvider) ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Categorías')),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              key: const Key('category-add'),
              onPressed: () => _create(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Nueva categoría'),
            )
          : null,
      body: asyncView(
        ref.watch(clubCategoriesProvider),
        onRetry: () => ref.invalidate(clubCategoriesProvider),
        builder: (all) {
          final base = [
            for (final c in all)
              if (c.scope == CatalogScope.base) c,
          ];
          final own = [
            for (final c in all)
              if (c.scope == CatalogScope.club) c,
          ];
          return ListView(
            padding: const EdgeInsets.only(bottom: Espacio.xxxl * 2),
            children: [
              const SectionTitle('Base'),
              for (final c in base) _CategoryTile(category: c, canEdit: false),
              const SectionTitle('Del club'),
              if (own.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(Espacio.l),
                  child: Text('El club todavía no tiene categorías propias.'),
                ),
              for (final c in own) _CategoryTile(category: c, canEdit: canEdit),
            ],
          );
        },
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final clubId = ref.read(catalogClubIdProvider);
    final name = await _askName(context, title: 'Nueva categoría');
    if (name == null || clubId == null || !context.mounted) return;
    await _run(
      context,
      ref,
      () =>
          ref.read(catalogAdminRepositoryProvider).createCategory(clubId, name),
    );
  }
}

Future<void> _run(
  BuildContext context,
  WidgetRef ref,
  Future<Object?> Function() action, {
  String? notice,
}) async {
  try {
    await action();
    ref.invalidate(clubCategoriesProvider);
    if (notice != null && context.mounted) showNotice(context, notice);
  } catch (e) {
    if (context.mounted) showApiError(context, e);
  }
}

Future<String?> _askName(
  BuildContext context, {
  required String title,
  String initial = '',
}) => showDialog<String>(
  context: context,
  builder: (context) => _NameDialog(title: title, initial: initial),
);

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: const Key('category-name'),
      controller: _controller,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Nombre'),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('category-save'),
        onPressed: _submit,
        child: const Text('Guardar'),
      ),
    ],
  );
}

enum _Action { rename, toggle, delete }

class _CategoryTile extends ConsumerWidget {
  const _CategoryTile({required this.category, required this.canEdit});

  final Category category;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archived = category.status == CatalogStatus.archived;
    return ListTile(
      key: Key('category-${category.id}'),
      title: Text(category.name),
      subtitle: archived ? const Text('Archivada') : null,
      leading: Icon(
        category.scope == CatalogScope.base
            ? Icons.lock_outline
            : Icons.label_outline,
      ),
      trailing: canEdit
          ? PopupMenuButton<_Action>(
              key: Key('category-menu-${category.id}'),
              onSelected: (a) => _act(context, ref, a),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: _Action.rename,
                  child: Text('Renombrar'),
                ),
                PopupMenuItem(
                  value: _Action.toggle,
                  child: Text(archived ? 'Reactivar' : 'Archivar'),
                ),
                const PopupMenuItem(
                  value: _Action.delete,
                  child: Text('Borrar'),
                ),
              ],
            )
          : null,
    );
  }

  Future<void> _act(BuildContext context, WidgetRef ref, _Action action) async {
    final clubId = ref.read(catalogClubIdProvider);
    if (clubId == null) return;
    final repo = ref.read(catalogAdminRepositoryProvider);
    switch (action) {
      case _Action.rename:
        final name = await _askName(
          context,
          title: 'Renombrar categoría',
          initial: category.name,
        );
        if (name == null || !context.mounted) return;
        await _run(
          context,
          ref,
          () => repo.renameCategory(clubId, category.id, name),
        );
      case _Action.toggle:
        final next = category.status == CatalogStatus.archived
            ? CatalogStatus.active
            : CatalogStatus.archived;
        await _run(
          context,
          ref,
          () => repo.setCategoryStatus(clubId, category.id, next),
        );
      case _Action.delete:
        final ok = await confirmAction(
          context,
          title: 'Borrar categoría',
          body: 'Si algún ejercicio la usa, se archiva en vez de borrarse.',
          action: 'Borrar',
        );
        if (!ok || !context.mounted) return;
        try {
          final outcome = await repo.deleteCategory(clubId, category.id);
          ref.invalidate(clubCategoriesProvider);
          if (context.mounted) {
            showNotice(
              context,
              outcome == RemovalOutcome.deleted
                  ? 'Categoría borrada.'
                  : 'La categoría está en uso: quedó archivada.',
            );
          }
        } catch (e) {
          if (context.mounted) showApiError(context, e);
        }
    }
  }
}
