import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../features/sesion/presentation/providers.dart' show preloadDaysProvider;
import 'preferencias.dart';
import 'router.dart';

class MaktubApp extends ConsumerWidget {
  const MaktubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferencia = ref.watch(preferenciaTemaProvider);
    // Today and the next days stay on the device for opening without signal (E7.15).
    ref.listen(preloadDaysProvider, (_, _) {});
    return MaterialApp.router(
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
