import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../features/access/presentation/providers.dart';
import '../features/atletas/presentation/athlete_sheet_page.dart';
import '../features/atletas/presentation/athletes_page.dart';
import '../features/catalogo/presentation/catalog_routes.dart';
import '../features/catalogo/presentation/categories_page.dart';
import '../features/catalogo/presentation/team_page.dart';
import '../features/catalogo/presentation/timers_page.dart';
import '../features/members/presentation/members_page.dart';
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

  /// The coach's athlete list; each athlete's sheet is `<atletas>/<athleteId>`.
  static const atletas = '$planificacion/atletas';

  /// What configures the club rather than a plan: catalog, timers, equipment and members.
  static const preferencias = '/preferencias';
  static const catalogo = '$preferencias/catalogo';
  static const categorias = '$preferencias/categorias';
  static const temporizadores = '$preferencias/temporizadores';
  static const equipo = '$preferencias/equipo';
  static const miembros = '$preferencias/miembros';

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
  final canPlan = ValueNotifier<bool?>(ref.read(canPlanProvider));
  ref.listen(canPlanProvider, (_, value) => canPlan.value = value);
  ref.onDispose(canPlan.dispose);
  final canConfigure = ValueNotifier<bool?>(ref.read(canConfigureProvider));
  ref.listen(canConfigureProvider, (_, value) => canConfigure.value = value);
  ref.onDispose(canConfigure.dispose);

  final router = GoRouter(
    initialLocation: Rutas.entrenamiento,
    refreshListenable: Listenable.merge([session, canPlan, canConfigure]),
    redirect: (context, state) =>
        sessionRedirect(session.value, state.uri, canPlan: canPlan.value, canConfigure: canConfigure.value),
    routes: [
      GoRoute(path: Rutas.signIn, builder: (_, _) => const SignInPage()),
      GoRoute(path: Rutas.restoring, builder: (_, _) => const SessionRestoringPage()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navegacion) => ShellPrincipal(navegacion: navegacion),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: Rutas.entrenamiento,
              builder: (_, _) => const PaginaEntrenamiento(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Rutas.planificacion,
              builder: (_, _) => const PaginaPlanificacion(),
              routes: [
                GoRoute(
                  path: 'atletas',
                  builder: (_, _) => const AthletesPage(basePath: Rutas.atletas),
                  routes: [
                    GoRoute(
                      path: ':id',
                      builder: (_, state) => AthleteSheetPage(athleteId: state.pathParameters['id']!),
                    ),
                  ],
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Rutas.preferencias,
              builder: (_, _) => const PaginaPreferencias(),
              routes: [
                exerciseCatalogRoute(),
                GoRoute(path: 'categorias', builder: (_, _) => const CategoriesPage()),
                GoRoute(path: 'temporizadores', builder: (_, _) => const TimersPage()),
                GoRoute(path: 'equipo', builder: (_, _) => const TeamPage()),
                GoRoute(path: 'miembros', builder: (_, _) => const MembersPage()),
              ],
            ),
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
