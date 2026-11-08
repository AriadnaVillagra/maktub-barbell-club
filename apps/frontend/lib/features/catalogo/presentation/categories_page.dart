import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../access/presentation/providers.dart';
import '../domain/catalog_admin_repository.dart';
import '../domain/catalog_filters.dart';
import 'catalog_admin_providers.dart';
import 'catalog_admin_widgets.dart';
import 'providers.dart';

/// Default and custom categories in a single filterable list. Tapping one renames it, for whoever can
/// change it (platform admin for default ones, club admin for the club's).
class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});

  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage> {
  ScopeFilter _scope = ScopeFilter.all;
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final canCreate = ref.watch(canEditClubCatalogProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Categorías')),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              key: const Key('category-add'),
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('Nueva categoría'),
            )
          : null,
      body: asyncView(
        ref.watch(clubCategoriesProvider),
        onRetry: () => ref.invalidate(clubCategoriesProvider),
        builder: (all) {
          final shown = [
            for (final c in all)
              if (matchesCatalogFilters(c, c.status, scope: _scope, showArchived: _showArchived)) c,
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CatalogFilters(
                scope: _scope,
                onScope: (v) => setState(() => _scope = v),
                showArchived: _showArchived,
                onShowArchived: (v) => setState(() => _showArchived = v),
                archivedLabel: 'Solo archivadas',
              ),
              Expanded(
                child: shown.isEmpty
                    ? const Center(child: Text('No hay categorías.'))
                    : ListView(
                        padding: const EdgeInsets.only(bottom: Espacio.xxxl * 2),
                        children: [for (final c in shown) _CategoryTile(category: c)],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _create() async {
    final clubId = ref.read(catalogClubIdProvider);
    final name = await _askName(context, title: 'Nueva categoría');
    if (name == null || clubId == null || !mounted) return;
    await _run(context, ref, () => ref.read(catalogAdminRepositoryProvider).createCategory(clubId, name));
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
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(key: const Key('category-save'), onPressed: _submit, child: const Text('Guardar')),
    ],
  );
}

enum _Action { toggle, delete }

class _CategoryTile extends ConsumerWidget {
  const _CategoryTile({required this.category});

  final Category category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archived = category.status == CatalogStatus.archived;
    final canWrite = ref.watch(canWriteCatalogProvider)(category);
    return ListTile(
      key: Key('category-${category.id}'),
      leading: const Icon(Icons.fitness_center),
      title: Text(category.name),
      subtitle: archived ? const Text('Archivada') : null,
      onTap: canWrite ? () => _rename(context, ref) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Espacio.s,
        children: [
          ScopeBadge(category.scope),
          if (canWrite)
            PopupMenuButton<_Action>(
              key: Key('category-menu-${category.id}'),
              onSelected: (a) => _act(context, ref, a),
              itemBuilder: (_) => [
                PopupMenuItem(value: _Action.toggle, child: Text(archived ? 'Reactivar' : 'Archivar')),
                const PopupMenuItem(value: _Action.delete, child: Text('Borrar')),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final clubId = ref.read(catalogClubIdProvider);
    if (clubId == null) return;
    final repo = ref.read(catalogAdminRepositoryProvider);
    final name = await _askName(context, title: 'Editar categoría', initial: category.name);
    if (name == null || !context.mounted) return;
    await _run(context, ref, () => repo.renameCategory(clubId, category.id, name));
  }

  Future<void> _act(BuildContext context, WidgetRef ref, _Action action) async {
    final clubId = ref.read(catalogClubIdProvider);
    if (clubId == null) return;
    final repo = ref.read(catalogAdminRepositoryProvider);
    switch (action) {
      case _Action.toggle:
        final next = category.status == CatalogStatus.archived ? CatalogStatus.active : CatalogStatus.archived;
        await _run(context, ref, () => repo.setCategoryStatus(clubId, category.id, next));
      case _Action.delete:
        final ok = await confirmAction(
          context,
          title: 'Borrar categoría',
          body: category.scope == CatalogScope.base
              ? 'Es una categoría default: desaparece para todos los clubes. Si algún ejercicio la usa, se archiva en vez de borrarse.'
              : 'Si algún ejercicio la usa, se archiva en vez de borrarse.',
          action: 'Borrar',
        );
        if (!ok || !context.mounted) return;
        try {
          final outcome = await repo.deleteCategory(clubId, category.id);
          ref.invalidate(clubCategoriesProvider);
          if (context.mounted) {
            showNotice(
              context,
              outcome == RemovalOutcome.deleted ? 'Categoría borrada.' : 'La categoría está en uso: quedó archivada.',
            );
          }
        } catch (e) {
          if (context.mounted) showApiError(context, e);
        }
    }
  }
}
