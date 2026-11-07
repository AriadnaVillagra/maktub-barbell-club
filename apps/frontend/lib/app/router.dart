import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_ui/maktub_ui.dart';

import 'modos.dart';
import 'shell.dart';

/// Rutas de primer nivel: los dos modos de la app (docs/diseno.md, "Visión").
/// Cada feature agrega sus rutas como hijas del modo al que pertenece.
abstract final class Rutas {
  static const entrenamiento = '/entrenamiento';
  static const planificacion = '/planificacion';

  /// Galería del design system. Solo existe en builds de desarrollo.
  static const galeria = '/galeria';
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: Rutas.entrenamiento,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navegacion) => ShellPrincipal(navegacion: navegacion),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: Rutas.entrenamiento, builder: (_, _) => const PaginaEntrenamiento()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Rutas.planificacion, builder: (_, _) => const PaginaPlanificacion()),
          ]),
        ],
      ),
      if (kDebugMode) GoRoute(path: Rutas.galeria, builder: (_, _) => const GaleriaMaktub()),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('No existe la página ${state.uri.path}')),
    ),
  );
  ref.onDispose(router.dispose);
  return router;
});
