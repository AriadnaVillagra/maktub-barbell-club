import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../access/presentation/providers.dart';
import '../domain/catalog_admin_repository.dart';
import 'catalog_admin_providers.dart';
import 'catalog_admin_widgets.dart';
import 'providers.dart';
import 'timer_form.dart';

/// The timers available to the club: base ones are fixed, coaches create, edit, archive and delete
/// the club's own. Anyone else only reads (F2 §5, §6).
class TimersPage extends ConsumerWidget {
  const TimersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit = ref.watch(canPlanProvider) ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Temporizadores')),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              key: const Key('timer-add'),
              onPressed: () => _edit(context, ref, null),
              icon: const Icon(Icons.add),
              label: const Text('Nuevo temporizador'),
            )
          : null,
      body: asyncView(
        ref.watch(clubTimersProvider),
        onRetry: () => ref.invalidate(clubTimersProvider),
        builder: (all) {
          final base = [
            for (final t in all)
              if (scopeOf(t) == CatalogScope.base) t,
          ];
          final own = [
            for (final t in all)
              if (scopeOf(t) == CatalogScope.club) t,
          ];
          return ListView(
            padding: const EdgeInsets.only(bottom: Espacio.xxxl * 2),
            children: [
              const SectionTitle('Base'),
              for (final t in base)
                _TimerTile(timer: t, canEdit: false, onEdit: () {}),
              const SectionTitle('Del club'),
              if (own.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(Espacio.l),
                  child: Text(
                    'El club todavía no tiene temporizadores propios.',
                  ),
                ),
              for (final t in own)
                _TimerTile(
                  timer: t,
                  canEdit: canEdit,
                  onEdit: () => _edit(context, ref, t),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Temporizador? timer,
  ) async {
    final clubId = ref.read(catalogClubIdProvider);
    final edited = await showTimerForm(context, initial: timer);
    if (edited == null || clubId == null || !context.mounted) return;
    final repo = ref.read(catalogAdminRepositoryProvider);
    await _guard(
      context,
      ref,
      () => timer == null
          ? repo.createTimer(clubId, edited)
          : repo.updateTimer(clubId, edited),
    );
  }
}

Future<void> _guard(
  BuildContext context,
  WidgetRef ref,
  Future<Object?> Function() action,
) async {
  try {
    await action();
    ref.invalidate(clubTimersProvider);
  } catch (e) {
    if (context.mounted) showApiError(context, e);
  }
}

enum _Action { edit, toggle, delete }

class _TimerTile extends ConsumerWidget {
  const _TimerTile({
    required this.timer,
    required this.canEdit,
    required this.onEdit,
  });

  final Temporizador timer;
  final bool canEdit;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archived = timer.estado == CatalogStatus.archived;
    return ListTile(
      key: Key('timer-${timer.id}'),
      leading: Icon(
        scopeOf(timer) == CatalogScope.base
            ? Icons.lock_outline
            : Icons.timer_outlined,
      ),
      title: Text(timer.nombre),
      subtitle: Text(
        archived
            ? '${describirTemporizador(timer)} · Archivado'
            : describirTemporizador(timer),
      ),
      trailing: canEdit
          ? PopupMenuButton<_Action>(
              key: Key('timer-menu-${timer.id}'),
              onSelected: (a) => _act(context, ref, a),
              itemBuilder: (_) => [
                const PopupMenuItem(value: _Action.edit, child: Text('Editar')),
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
      case _Action.edit:
        onEdit();
      case _Action.toggle:
        await _guard(
          context,
          ref,
          () => timer.estado == CatalogStatus.archived
              ? repo.updateTimer(
                  clubId,
                  timer.copyWith(estado: CatalogStatus.active),
                )
              : repo.archiveTimer(clubId, timer.id),
        );
      case _Action.delete:
        final ok = await confirmAction(
          context,
          title: 'Borrar temporizador',
          body: 'Si ya se usa, se archiva en vez de borrarse.',
          action: 'Borrar',
        );
        if (!ok || !context.mounted) return;
        try {
          final outcome = await repo.deleteTimer(clubId, timer.id);
          ref.invalidate(clubTimersProvider);
          if (context.mounted) {
            showNotice(
              context,
              outcome == RemovalOutcome.deleted
                  ? 'Temporizador borrado.'
                  : 'El temporizador está en uso: quedó archivado.',
            );
          }
        } catch (e) {
          if (context.mounted) showApiError(context, e);
        }
    }
  }
}
