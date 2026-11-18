import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../core/pwa/app_update.dart';
import '../features/sesion/presentation/providers.dart' show preloadDaysProvider;
import 'preferencias.dart';
import 'router.dart';

class MaktubApp extends ConsumerStatefulWidget {
  const MaktubApp({super.key});

  @override
  ConsumerState<MaktubApp> createState() => _MaktubAppState();
}

class _MaktubAppState extends ConsumerState<MaktubApp> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  /// A new version already downloaded: it stays offered until it is applied, since applying reloads the page and
  /// that is the user's call (they may be in the middle of a set).
  void _offerUpdate() => WidgetsBinding.instance.addPostFrameCallback((_) {
    _messenger.currentState?.showSnackBar(
      SnackBar(
        key: const Key('app-update'),
        content: const Text('Hay una versión nueva'),
        duration: const Duration(days: 1),
        showCloseIcon: true,
        action: SnackBarAction(
          label: 'Actualizar',
          onPressed: () => ref.read(appUpdateProvider).apply(),
        ),
      ),
    );
  });

  @override
  void initState() {
    super.initState();
    if (ref.read(appUpdateReadyProvider)) _offerUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final preferencia = ref.watch(preferenciaTemaProvider);
    // Today and the next days stay on the device for opening without signal (E7.15).
    ref.listen(preloadDaysProvider, (_, _) {});
    ref.listen(appUpdateReadyProvider, (before, ready) {
      if (ready && before != true) _offerUpdate();
    });
    return MaterialApp.router(
      scaffoldMessengerKey: _messenger,
      title: 'Maktub Barbell Club',
      debugShowCheckedModeBanner: false,
      // Tema base (planificación). El shell aplica el tema de cada modo con TemaDeModo.
      theme: TemaMaktub.claro(),
      darkTheme: TemaMaktub.oscuro(),
      themeMode: switch (preferencia) {
        PreferenciaTema.sistema => ThemeMode.system,
        PreferenciaTema.claro => ThemeMode.light,
        PreferenciaTema.oscuro => ThemeMode.dark,
      },
      routerConfig: ref.watch(routerProvider),
    );
  }
}
