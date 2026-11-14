import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../../../catalogo/presentation/catalog_admin_providers.dart' show clubTimersProvider;
import '../controllers/crono_controller.dart';
import 'selector_temporizador.dart';

/// Opens the picker with the club's active timers and starts the chosen one. It runs in the timer bar
/// of the shell, so it is reachable from any screen, as in the reference (the ⏱ in every header).
Future<void> pickAndStartTimer(BuildContext context, WidgetRef ref) async {
  final crono = ref.read(cronoControllerProvider.notifier);
  // Without signal and nothing loaded yet, the picker opens empty instead of failing.
  final timers = ref.read(clubTimersProvider).value ??
      await ref.read(clubTimersProvider.future).catchError((Object _) => const <Temporizador>[]);
  if (!context.mounted) return;
  final chosen = await elegirTemporizador(context, [
    for (final t in timers)
      if (t.estado == CatalogStatus.active) t,
  ]);
  if (chosen != null) crono.iniciar(chosen);
}
