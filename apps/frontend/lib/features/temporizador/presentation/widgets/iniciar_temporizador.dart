import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_core/maktub_core.dart';

import '../../../catalogo/presentation/catalog_admin_providers.dart' show clubTimersProvider;
import '../controllers/crono_controller.dart';
import '../quick_timers_providers.dart';
import 'selector_temporizador.dart';

/// Opens the picker with the timers the user keeps at hand and starts the chosen one. It runs in the timer bar
/// of the shell, so it is reachable from any screen, as in the reference (the ⏱ in every header). [configurePath] is
/// where those are chosen (Preferencias → Temporizadores); without it (in the middle of a session) the picker does not
/// offer to go there.
Future<void> pickAndStartTimer(BuildContext context, WidgetRef ref, {String? configurePath}) async {
  final crono = ref.read(cronoControllerProvider.notifier);
  // Without signal and nothing loaded yet, the picker opens empty instead of failing.
  final timers = ref.read(clubTimersProvider).value ??
      await ref.read(clubTimersProvider.future).catchError((Object _) => const <Temporizador>[]);
  // Without signal the choice may not be known: then every active timer, so the button still works.
  final quick = ref.read(quickTimerIdsProvider).value ??
      await ref.read(quickTimerIdsProvider.future).then<List<String>?>((v) => v).catchError((Object _) => null);
  if (!context.mounted) return;
  final active = {
    for (final t in timers)
      if (t.estado == CatalogStatus.active) t.id: t,
  };
  final chosen = await elegirTemporizador(
    context,
    quick == null ? active.values : [for (final id in quick) ?active[id]],
    onConfigure: configurePath == null ? null : () => context.go(configurePath),
  );
  if (chosen != null) crono.iniciar(chosen);
}
