import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../catalogo/presentation/catalog_admin_providers.dart';
import '../../catalogo/presentation/catalog_admin_widgets.dart'
    show asyncView, confirmAction, showApiError, showNotice;
import '../../catalogo/presentation/providers.dart';
import 'providers.dart';
import 'wod_labels.dart';

/// The club's library of WoDs, by name: the way into each WoD's editor, where a new one is created and where
/// one is deleted. Coach only (the API enforces it).
class WodsPage extends ConsumerWidget {
  const WodsPage({super.key, required this.basePath});

  /// The route of this page; `<basePath>/nuevo` creates and `<basePath>/<wodId>` edits.
  final String basePath;

  Future<void> _delete(BuildContext context, WidgetRef ref, Wod wod) async {
    final ok = await confirmAction(
      context,
      title: 'Borrar WoD',
      body:
          'Se borra "${wod.name}" de la biblioteca. Los planes que ya lo copiaron lo conservan.',
      action: 'Borrar',
    );
    final clubId = ref.read(catalogClubIdProvider);
    if (!ok || clubId == null || !context.mounted) return;
    try {
      await ref.read(wodRepositoryProvider).delete(clubId, wod.id);
      ref.invalidate(wodsProvider);
      if (context.mounted) showNotice(context, 'WoD borrado.');
    } catch (e) {
      if (context.mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timers = ref.watch(clubTimersProvider).value ?? const [];
    String? timerName(String? id) {
      for (final t in timers) {
        if (t.id == id) return t.nombre;
      }
      return null;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('WoDs')),
      floatingActionButton: FloatingActionButton(
        key: const Key('wod-add'),
        tooltip: 'Nuevo WoD',
        onPressed: () => context.go('$basePath/nuevo'),
        child: const Icon(Icons.add),
      ),
      body: asyncView(
        ref.watch(wodsProvider),
        onRetry: () => ref.invalidate(wodsProvider),
        builder: (wods) => wods.isEmpty
            ? const Center(
                child: Text(
                  'Todavía no hay WoDs en la biblioteca.',
                  key: Key('wods-empty'),
                ),
              )
            : ListView(
                // Keeps the rows out of the add button's column, so it never covers them.
                padding: const EdgeInsets.only(
                  right:
                      kFloatingActionButtonMargin +
                      kMinInteractiveDimension +
                      Espacio.l,
                ),
                children: [
                  for (final w in wods)
                    ListTile(
                      key: Key('wod-${w.id}'),
                      leading: const Icon(Icons.local_fire_department_outlined),
                      title: Text(w.name),
                      subtitle: Text(
                        wodSummary(w, timerName: timerName(w.timerId)),
                      ),
                      onTap: () =>
                          context.go('$basePath/${Uri.encodeComponent(w.id)}'),
                      trailing: IconButton(
                        key: Key('wod-delete-${w.id}'),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Borrar WoD',
                        onPressed: () => _delete(context, ref, w),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
