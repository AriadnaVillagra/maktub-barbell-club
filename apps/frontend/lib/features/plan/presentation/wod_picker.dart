import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../../catalogo/presentation/catalog_admin_providers.dart';
import '../../catalogo/presentation/catalog_admin_widgets.dart' show asyncView;
import '../../wods/presentation/providers.dart';
import '../../wods/presentation/wod_labels.dart';

/// Opens the library of WoDs in a modal bottom sheet. Resolves to the chosen WoD, or null when the sheet is
/// dismissed. It lists every WoD of the club, by name.
Future<Wod?> showWodPicker(BuildContext context) => showModalBottomSheet<Wod>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) =>
      const FractionallySizedBox(heightFactor: 0.9, child: _WodPicker()),
);

class _WodPicker extends ConsumerWidget {
  const _WodPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timers = ref.watch(clubTimersProvider).value ?? const [];
    String? timerName(String? id) {
      for (final t in timers) {
        if (t.id == id) return t.nombre;
      }
      return null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(Espacio.l),
          child: Text('Agregar WoD', style: context.textos.titleMedium),
        ),
        Expanded(
          child: asyncView(
            ref.watch(wodsProvider),
            onRetry: () => ref.invalidate(wodsProvider),
            builder: (wods) => wods.isEmpty
                ? const Center(
                    child: Text(
                      'Todavía no hay WoDs en la biblioteca.',
                      key: Key('wod-picker-empty'),
                    ),
                  )
                : ListView(
                    children: [
                      for (final w in wods)
                        ListTile(
                          key: Key('wod-pick-${w.id}'),
                          title: Text(w.name),
                          subtitle: Text(
                            wodSummary(w, timerName: timerName(w.timerId)),
                          ),
                          onTap: () => Navigator.of(context).pop(w),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
