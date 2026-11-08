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
import 'timer_form.dart';

/// Default and custom timers in a single filterable list. Tapping one edits it, for whoever can change
/// it (platform admin for default ones, club admin for the club's).
class TimersPage extends ConsumerStatefulWidget {
  const TimersPage({super.key});

  @override
  ConsumerState<TimersPage> createState() => _TimersPageState();
}

class _TimersPageState extends ConsumerState<TimersPage> {
  ScopeFilter _scope = ScopeFilter.all;
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final canCreate = ref.watch(canEditClubCatalogProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Temporizadores')),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              key: const Key('timer-add'),
              onPressed: () => _edit(null),
              icon: const Icon(Icons.add),
              label: const Text('Nuevo temporizador'),
            )
          : null,
      body: asyncView(
        ref.watch(clubTimersProvider),
        onRetry: () => ref.invalidate(clubTimersProvider),
        builder: (all) {
          final shown = [
            for (final t in all)
              if (matchesCatalogFilters(t, t.estado, scope: _scope, showArchived: _showArchived)) t,
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CatalogFilters(
                scope: _scope,
                onScope: (v) => setState(() => _scope = v),
                showArchived: _showArchived,
                onShowArchived: (v) => setState(() => _showArchived = v),
                archivedLabel: 'Solo archivados',
              ),
              Expanded(
                child: shown.isEmpty
                    ? const Center(child: Text('No hay temporizadores.'))
                    : ListView(
                        padding: const EdgeInsets.only(bottom: Espacio.xxxl * 2),
                        children: [for (final t in shown) _TimerTile(timer: t, onEdit: () => _edit(t))],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(Temporizador? timer) async {
    final clubId = ref.read(catalogClubIdProvider);
    final repo = ref.read(catalogAdminRepositoryProvider);
    final edited = await showTimerForm(context, initial: timer);
    if (edited == null || clubId == null || !mounted) return;
    await _guard(context, ref, () => timer == null ? repo.createTimer(clubId, edited) : repo.updateTimer(clubId, edited));
  }
}

Future<void> _guard(BuildContext context, WidgetRef ref, Future<Object?> Function() action) async {
  try {
    await action();
    ref.invalidate(clubTimersProvider);
  } catch (e) {
    if (context.mounted) showApiError(context, e);
  }
}

enum _Action { toggle, delete }

class _TimerTile extends ConsumerWidget {
  const _TimerTile({required this.timer, required this.onEdit});

  final Temporizador timer;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archived = timer.estado == CatalogStatus.archived;
    final canWrite = ref.watch(canWriteCatalogProvider)(timer);
    return ListTile(
      key: Key('timer-${timer.id}'),
      leading: const Icon(Icons.timer_outlined),
      title: Text(timer.nombre),
      subtitle: Text(archived ? '${describirTemporizador(timer)} · Archivado' : describirTemporizador(timer)),
      onTap: canWrite ? onEdit : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Espacio.s,
        children: [
          ScopeBadge(scopeOf(timer)),
          if (canWrite)
            PopupMenuButton<_Action>(
              key: Key('timer-menu-${timer.id}'),
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

  Future<void> _act(BuildContext context, WidgetRef ref, _Action action) async {
    final clubId = ref.read(catalogClubIdProvider);
    if (clubId == null) return;
    final repo = ref.read(catalogAdminRepositoryProvider);
    switch (action) {
      case _Action.toggle:
        await _guard(
          context,
          ref,
          () => timer.estado == CatalogStatus.archived
              ? repo.updateTimer(clubId, timer.copyWith(estado: CatalogStatus.active))
              : repo.archiveTimer(clubId, timer.id),
        );
      case _Action.delete:
        final ok = await confirmAction(
          context,
          title: 'Borrar temporizador',
          body: scopeOf(timer) == CatalogScope.base
              ? 'Es un temporizador default: desaparece para todos los clubes. Si ya se usa, se archiva en vez de borrarse.'
              : 'Si ya se usa, se archiva en vez de borrarse.',
          action: 'Borrar',
        );
        if (!ok || !context.mounted) return;
        try {
          final outcome = await repo.deleteTimer(clubId, timer.id);
          ref.invalidate(clubTimersProvider);
          if (context.mounted) {
            showNotice(
              context,
              outcome == RemovalOutcome.deleted ? 'Temporizador borrado.' : 'El temporizador está en uso: quedó archivado.',
            );
          }
        } catch (e) {
          if (context.mounted) showApiError(context, e);
        }
    }
  }
}
