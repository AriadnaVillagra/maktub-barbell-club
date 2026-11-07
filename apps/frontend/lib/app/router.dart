import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../features/session/domain/session_manager.dart';
import '../features/session/presentation/providers.dart';
import '../features/session/presentation/sign_in_page.dart';
import 'modos.dart';
import 'session_redirect.dart';
import 'shell.dart';

/// Rutas de primer nivel: los dos modos de la app (docs/diseno.md, "Visión").
/// Cada feature agrega sus rutas como hijas del modo al que pertenece.
abstract final class Rutas {
  static const entrenamiento = '/entrenamiento';
  static const planificacion = '/planificacion';

  /// Sign-in with Google. Every route leads here without a session (see [sessionRedirect]).
  static const signIn = '/ingreso';

  /// While the saved tokens load.
  static const restoring = '/cargando';

  /// Galería del design system. Solo existe en builds de desarrollo.
  static const galeria = '/galeria';
}

final routerProvider = Provider<GoRouter>((ref) {
  final session = ValueNotifier<SessionStatus>(ref.read(sessionControllerProvider));
  ref.listen(sessionControllerProvider, (_, status) => session.value = status);
  ref.onDispose(session.dispose);

  final router = GoRouter(
    initialLocation: Rutas.entrenamiento,
    refreshListenable: session,
    redirect: (context, state) => sessionRedirect(session.value, state.uri),
    routes: [
      GoRoute(path: Rutas.signIn, builder: (_, _) => const SignInPage()),
      GoRoute(path: Rutas.restoring, builder: (_, _) => const SessionRestoringPage()),
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
