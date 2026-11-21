import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../catalogo/presentation/catalog_admin_widgets.dart' show asyncView;
import 'providers.dart';

/// The club's athletes: the way into each athlete's sheet. Coach only.
class AthletesPage extends ConsumerWidget {
  const AthletesPage({super.key, required this.basePath});

  /// The route of this page; a sheet lives at `<basePath>/<athleteId>`.
  final String basePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Atletas y referencias')),
    body: asyncView(
      ref.watch(athletesProvider),
      onRetry: () => ref.invalidate(athletesProvider),
      builder: (athletes) => athletes.isEmpty
          ? const Center(
              child: Text(
                'Todavía no hay atletas en el club.',
                key: Key('athletes-empty'),
              ),
            )
          : ListView(
              children: [
                for (final a in athletes)
                  ListTile(
                    key: Key('athlete-${a.id}'),
                    leading: const Icon(Icons.person_outline),
                    title: Text(a.name),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: Key('athlete-history-${a.id}'),
                          icon: const Icon(Icons.history),
                          tooltip: 'Historial',
                          onPressed: () => context.go('$basePath/${Uri.encodeComponent(a.id)}/historial'),
                        ),
                        const SizedBox(width: Espacio.xl),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () =>
                        context.go('$basePath/${Uri.encodeComponent(a.id)}'),
                  ),
              ],
            ),
    ),
  );
}
