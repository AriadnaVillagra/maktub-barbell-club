import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../core/refresh/refresh_on_return.dart';
import '../features/access/presentation/club_picker_page.dart';
import '../features/access/presentation/providers.dart';
import '../features/asignacion/presentation/providers.dart' show clubAssignmentsProvider;
import '../features/atletas/presentation/providers.dart' show athletesProvider;
import '../features/catalogo/presentation/catalog_admin_providers.dart'
    show clubCategoriesProvider, clubTeamProvider, clubTimersProvider;
import '../features/plan/presentation/providers.dart' show plansProvider;
import '../features/wods/presentation/providers.dart' show wodsProvider;
import '../features/asignacion/presentation/assignments_page.dart';
import '../features/atletas/presentation/athlete_sheet_page.dart';
import '../features/atletas/presentation/athletes_page.dart';
import '../features/atletas/presentation/profile_page.dart';
import '../features/catalogo/presentation/catalog_routes.dart';
import '../features/catalogo/presentation/categories_page.dart';
import '../features/catalogo/presentation/team_page.dart';
import '../features/history/presentation/history_page.dart';
import '../features/history/presentation/session_history_page.dart';
import '../features/catalogo/presentation/timers_page.dart';
import '../features/plan/presentation/plan_editor_page.dart';
import '../features/wods/presentation/wod_editor_page.dart';
import '../features/wods/presentation/wods_page.dart';
import '../features/plan/presentation/plans_page.dart';
import '../features/club_requests/presentation/club_requests_page.dart';
import '../features/members/presentation/members_page.dart';
import '../features/sesion/presentation/guided_page.dart';
import '../features/sesion/presentation/session_page.dart';
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

  /// The plan's calendar for the group, read-only; both coach and athlete.
  static const calendario = '$entrenamiento/calendario';

  /// The day's session.
  static const sesion = '$entrenamiento/sesion';

  /// The guided mode "Entrenar" over the open session.
  static const entrenar = '$sesion/entrenar';

  /// The coach's athlete list; each athlete's sheet is `<atletas>/<athleteId>`.
  static const atletas = '$planificacion/atletas';

  /// The coach's plan list; a plan's editor is `<planes>/<planId>`.
  static const planes = '$planificacion/planes';

  /// The group's plan assignments.
  static const asignaciones = '$planificacion/asignaciones';

  /// What configures the club rather than a plan: catalog, timers, equipment and members.
  static const preferencias = '/preferencias';
  static const catalogo = '$preferencias/catalogo';
  static const categorias = '$preferencias/categorias';
  static const temporizadores = '$preferencias/temporizadores';
  static const wods = '$preferencias/wods';
  static const equipo = '$preferencias/equipo';
  static const miembros = '$preferencias/miembros';

  /// Club requests from people without an account; only platform admins see it.
  static const pedidosClub = '$preferencias/pedidos-club';

  /// Every club of the platform, to work in any of them; only platform admins see it.
  static const club = '$preferencias/club';

  /// The athlete's own read-only references.
  static const perfil = '/perfil';

  /// The athlete's own past sessions, in training mode; one session is `<historial>/<sessionId>`.
  static const historial = '$entrenamiento/historial';

  /// Where the own history used to live (under Perfil); old links are redirected to [historial].
  static const historialAntiguo = '$perfil/historial';

  /// An athlete's past sessions as the coach reads them, from their sheet; one session is `<that>/<sessionId>`.
  static String historialDeAtleta(String athleteId) => '$atletas/${Uri.encodeComponent(athleteId)}/historial';

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

  final hasProfile = ValueNotifier<bool?>(ref.read(hasAthleteProfileProvider));
  ref.listen(hasAthleteProfileProvider, (_, value) => hasProfile.value = value);
  ref.onDispose(hasProfile.dispose);

  final router = GoRouter(
    initialLocation: Rutas.entrenamiento,
    refreshListenable: Listenable.merge([session, canPlan, canConfigure, hasProfile]),
    redirect: (context, state) =>
        sessionRedirect(
      session.value,
      state.uri,
      canPlan: canPlan.value,
      canConfigure: canConfigure.value,
      hasProfile: hasProfile.value,
    ),
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
              routes: [
                GoRoute(
                  path: 'sesion',
                  builder: (_, _) => const SessionPage(
                    guidedPath: Rutas.entrenar,
                    assignmentsPath: Rutas.asignaciones,
                  ),
                  routes: [
                    GoRoute(
                      path: 'entrenar',
                      builder: (_, _) => const GuidedPage(sessionPath: Rutas.sesion),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'historial',
                  builder: (_, _) => const OwnHistoryPage(basePath: Rutas.historial),
                  routes: [
                    GoRoute(
                      path: ':sessionId',
                      builder: (_, state) => OwnSessionHistoryPage(sessionId: state.pathParameters['sessionId']!),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'calendario',
                  builder: (_, _) => const SessionPage(
                    guidedPath: Rutas.entrenar,
                    assignmentsPath: Rutas.asignaciones,
                    initialView: SessionView.calendar,
                  ),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Rutas.planificacion,
              builder: (_, _) => const PaginaPlanificacion(),
              routes: [
                GoRoute(
                  path: 'atletas',
                  builder: (_, _) => RefreshOnReturn(
                    providers: [athletesProvider],
                    child: const AthletesPage(basePath: Rutas.atletas),
                  ),
                  routes: [
                    GoRoute(
                      path: ':id',
                      builder: (_, state) => AthleteSheetPage(
                        athleteId: state.pathParameters['id']!,
                        historyPath: Rutas.historialDeAtleta(state.pathParameters['id']!),
                      ),
                      routes: [
                        GoRoute(
                          path: 'historial',
                          builder: (_, state) => CoachHistoryPage(
                            athleteId: state.pathParameters['id']!,
                            basePath: Rutas.historialDeAtleta(state.pathParameters['id']!),
                          ),
                          routes: [
                            GoRoute(
                              path: ':sessionId',
                              builder: (_, state) => SessionHistoryPage(
                                athleteId: state.pathParameters['id']!,
                                sessionId: state.pathParameters['sessionId']!,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                GoRoute(
                  path: 'asignaciones',
                  builder: (_, _) => RefreshOnReturn(
                    providers: [clubAssignmentsProvider, plansProvider],
                    child: const AssignmentsPage(),
                  ),
                ),
                GoRoute(
                  path: 'planes',
                  builder: (_, _) => const PlansPage(basePath: Rutas.planes),
                  routes: [
                    GoRoute(
                      path: ':id',
                      builder: (_, state) =>
                          PlanEditorPage(planId: state.pathParameters['id']!, listPath: Rutas.planes),
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
                GoRoute(
                  path: 'categorias',
                  builder: (_, _) => RefreshOnReturn(providers: [clubCategoriesProvider], child: const CategoriesPage()),
                ),
                GoRoute(
                  path: 'temporizadores',
                  builder: (_, _) => RefreshOnReturn(providers: [clubTimersProvider], child: const TimersPage()),
                ),
                GoRoute(
                  path: 'wods',
                  builder: (_, _) => RefreshOnReturn(
                    providers: [wodsProvider],
                    child: const WodsPage(basePath: Rutas.wods),
                  ),
                  routes: [
                    // Declared before ':id' so "nuevo" is not read as an id.
                    GoRoute(path: 'nuevo', builder: (_, _) => const WodEditorPage(listPath: Rutas.wods)),
                    GoRoute(
                      path: ':id',
                      builder: (_, state) =>
                          WodEditorPage(wodId: state.pathParameters['id']!, listPath: Rutas.wods),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'equipo',
                  builder: (_, _) => RefreshOnReturn(providers: [clubTeamProvider], child: const TeamPage()),
                ),
                GoRoute(path: 'miembros', builder: (_, _) => const MembersPage(exitPath: Rutas.preferencias)),
                GoRoute(path: 'pedidos-club', builder: (_, _) => const ClubRequestsPage()),
                GoRoute(path: 'club', builder: (_, _) => const ClubPickerPage()),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Rutas.perfil,
              builder: (_, _) => const ProfilePage(),
              routes: [
                // Old links to the own history keep working: they land on the training branch.
                GoRoute(
                  path: 'historial',
                  redirect: (_, state) => state.uri.toString().replaceFirst(Rutas.historialAntiguo, Rutas.historial),
                  routes: [
                    GoRoute(path: ':sessionId', builder: (_, _) => const SizedBox.shrink()),
                  ],
                ),
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
