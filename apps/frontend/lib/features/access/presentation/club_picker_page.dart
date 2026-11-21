import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../catalogo/presentation/catalog_admin_widgets.dart';
import 'providers.dart';

/// Every club of the platform, for a platform admin to work in any of them without a membership (support). Picking
/// one makes it the active club on this device, with every action.
class ClubPickerPage extends ConsumerWidget {
  const ClubPickerPage({super.key});

  Future<void> _choose(BuildContext context, WidgetRef ref, Club club) async {
    try {
      await chooseClub(ref, club);
      if (context.mounted) showNotice(context, 'Ahora trabajás en "${club.nombre}".');
    } catch (e) {
      if (context.mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(canPickAnyClubProvider)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Club')),
        body: const Center(child: Text('Solo un administrador de plataforma elige cualquier club.')),
      );
    }
    final activeId = ref.watch(meProvider).value?.activeClub?.club.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Club')),
      body: asyncView(
        ref.watch(allClubsProvider),
        onRetry: () => ref.invalidate(allClubsProvider),
        builder: (clubs) => clubs.isEmpty
            ? const Center(child: Text('Todavía no hay clubes.'))
            : ListView(
                padding: const EdgeInsets.all(Espacio.l),
                children: [
                  Text(
                    'Como administrador de plataforma podés entrar a cualquier club y hacer todo, aunque no seas miembro.',
                    style: context.textos.bodyMedium,
                  ),
                  const SizedBox(height: Espacio.l),
                  for (final club in clubs)
                    Card(
                      child: ListTile(
                        key: Key('club-picker-${club.id}'),
                        title: Text(club.nombre),
                        selected: club.id == activeId,
                        trailing: club.id == activeId ? const Icon(Icons.check) : null,
                        onTap: club.id == activeId ? null : () => _choose(context, ref, club),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
