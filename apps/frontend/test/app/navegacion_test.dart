import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/app/app.dart';
import 'package:maktub_frontend/app/router.dart';
import 'package:maktub_frontend/features/access/presentation/providers.dart';
import 'package:maktub_frontend/features/atletas/domain/athlete_repository.dart';
import 'package:maktub_frontend/features/atletas/presentation/providers.dart';
import 'package:maktub_frontend/features/catalogo/presentation/providers.dart';
import 'package:maktub_frontend/features/session/presentation/providers.dart';

import '../features/access/fakes.dart';
import '../features/atletas/fakes.dart';
import '../features/catalogo/catalog_fakes.dart';
import '../features/session/fakes.dart';

final _gym = club('c1', 'Gimnasio', TipoClub.club);

Future<void> _montar(
  WidgetTester tester,
  Size tamano, {
  Set<Rol> roles = const {Rol.coach},
  String? ruta,
  Map<String, String> athleteIds = const {},
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // Signed in: without a session the router would stop at the sign-in screen.
  await tester.pumpWidget(ProviderScope(
    overrides: [
      tokenStoreProvider.overrideWithValue(FakeTokenStore(issued(1))),
      authApiProvider.overrideWithValue(FakeAuthApi()),
      meRepositoryProvider.overrideWithValue(FakeMeRepository(meWith([(_gym, roles)], athleteIds: athleteIds))),
      catalogRepositoryProvider.overrideWithValue(FakeCatalog([])),
      athleteRepositoryProvider.overrideWithValue(FakeAthleteRepository(
        athletesList: const [AthleteSummary(id: 'a1', userId: 'u2', name: 'Andi')],
        sheets: {'a1': const AthleteSheet(athleteId: 'a1')},
      )),
    ],
    child: const MaktubApp(),
  ));
  await tester.pumpAndSettle();
  if (ruta != null) {
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(ruta);
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('arranca en Entrenamiento y navega a Planificación (celular)', (tester) async {
    await _montar(tester, const Size(400, 800));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Calendario'), findsOneWidget);

    await tester.tap(find.text('Planificación'));
    await tester.pumpAndSettle();

    expect(find.text('Atletas y referencias'), findsOneWidget);
    expect(find.text('Calendario'), findsNothing);
  });

  testWidgets('entrenamiento abre en oscuro y planificación sigue al sistema (claro)', (tester) async {
    await _montar(tester, const Size(400, 800));
    Brightness brillo() => Theme.of(tester.element(find.byType(NavigationBar))).brightness;

    expect(brillo(), Brightness.dark);

    await tester.tap(find.text('Planificación'));
    await tester.pumpAndSettle();

    expect(brillo(), Brightness.light);
  });

  testWidgets('en pantallas anchas usa un riel lateral', (tester) async {
    await _montar(tester, const Size(1200, 800));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  group('planning according to the role', () {
    testWidgets('an athlete does not see planning and has no bar with one destination', (tester) async {
      await _montar(tester, const Size(400, 800), roles: {Rol.atleta});

      expect(find.text('Calendario'), findsOneWidget);
      expect(find.text('Planificación'), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('an athlete is sent back to training when opening planning by URL', (tester) async {
      await _montar(tester, const Size(400, 800), roles: {Rol.atleta}, ruta: Rutas.planificacion);

      expect(find.text('Calendario'), findsOneWidget);
      expect(find.text('Atletas y referencias'), findsNothing);
    });

    testWidgets('an athlete on a wide screen has no rail either', (tester) async {
      await _montar(tester, const Size(1200, 800), roles: {Rol.atleta});

      expect(find.byType(NavigationRail), findsNothing);
      expect(find.text('Planificación'), findsNothing);
    });

    testWidgets('a coach sees planning and can open it by URL', (tester) async {
      await _montar(tester, const Size(400, 800), ruta: Rutas.planificacion);

      expect(find.text('Atletas y referencias'), findsOneWidget);
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('Planificación')), findsOneWidget);
    });

    testWidgets('a coach reaches the athlete sheet from the planning landing page', (tester) async {
      await _montar(tester, const Size(400, 800), ruta: Rutas.planificacion);

      await tester.tap(find.byKey(const Key('portada-${Rutas.atletas}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('athlete-a1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('athlete-a1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sheet-empty')), findsOneWidget);
      expect(find.text('Andi'), findsOneWidget);
    });

    testWidgets('an athlete is sent back to training when opening an athlete sheet by URL', (tester) async {
      await _montar(tester, const Size(400, 800), roles: {Rol.atleta}, ruta: '${Rutas.atletas}/a1');
      expect(find.text('Calendario'), findsOneWidget);
      expect(find.byKey(const Key('sheet-empty')), findsNothing);
    });

    testWidgets('a user without athlete id has no Perfil tab and is redirected from its route', (tester) async {
      await _montar(tester, const Size(400, 800), ruta: Rutas.perfil);

      expect(find.text('Calendario'), findsOneWidget);
      expect(find.byKey(const Key('sheet-empty')), findsNothing);
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('Perfil')), findsNothing);
    });

    for (final (name, size) in const [('phone', Size(400, 800)), ('tablet', Size(1200, 800))]) {
      testWidgets('a user with athlete id sees Perfil last on $name, read-only', (tester) async {
        await _montar(tester, size, athleteIds: {'c1': 'a1'});
        final bar = size.width < 600 ? find.byType(NavigationBar) : find.byType(NavigationRail);
        expect(find.descendant(of: bar, matching: find.text('Perfil')), findsOneWidget);

        await tester.tap(find.descendant(of: bar, matching: find.text('Perfil')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('sheet-empty')), findsOneWidget);
        expect(find.byKey(const Key('edit-rm')), findsNothing);
        // Light: Perfil follows the planning theme.
        expect(Theme.of(tester.element(bar)).brightness, Brightness.light);
      });
    }

    testWidgets('hiding Perfil does not shift the other tabs; an athlete-only user keeps Perfil', (tester) async {
      await _montar(tester, const Size(400, 800), roles: {Rol.atleta}, athleteIds: {'c1': 'a1'});
      expect(find.text('Calendario'), findsOneWidget);
      expect(find.text('Planificación'), findsNothing);
      expect(find.text('Perfil'), findsOneWidget);

      await _montar(tester, const Size(400, 800), ruta: Rutas.preferencias);
      await tester.tap(find.text('Planificación'));
      await tester.pumpAndSettle();
      expect(find.text('Atletas y referencias'), findsOneWidget);
    });

    testWidgets('the catalog lives in Preferences, not in training', (tester) async {
      await _montar(tester, const Size(400, 800));
      expect(find.text('Catálogo'), findsNothing);

      await tester.tap(find.text('Preferencias'));
      await tester.pumpAndSettle();

      expect(find.text('Ejercicios'), findsOneWidget);
      expect(find.text('Temporizadores'), findsOneWidget);
      expect(find.text('Miembros'), findsNothing);
    });

    testWidgets('a club admin also manages members', (tester) async {
      await _montar(tester, const Size(400, 800), roles: {Rol.coach, Rol.adminClub}, ruta: Rutas.preferencias);
      expect(find.text('Miembros'), findsOneWidget);
    });

    testWidgets('an athlete cannot open Preferences by URL', (tester) async {
      await _montar(tester, const Size(400, 800), roles: {Rol.atleta}, ruta: Rutas.preferencias);
      expect(find.text('Calendario'), findsOneWidget);
    });
  });
}
