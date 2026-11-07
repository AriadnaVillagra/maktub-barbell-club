import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/app/app.dart';
import 'package:maktub_frontend/app/router.dart';
import 'package:maktub_frontend/features/access/presentation/providers.dart';
import 'package:maktub_frontend/features/session/presentation/providers.dart';

import '../features/access/fakes.dart';
import '../features/session/fakes.dart';

final _gym = club('c1', 'Gimnasio', TipoClub.club);

Future<void> _montar(
  WidgetTester tester,
  Size tamano, {
  Set<Rol> roles = const {Rol.coach},
  String? ruta,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // Signed in: without a session the router would stop at the sign-in screen.
  await tester.pumpWidget(ProviderScope(
    overrides: [
      tokenStoreProvider.overrideWithValue(FakeTokenStore(issued(1))),
      authApiProvider.overrideWithValue(FakeAuthApi()),
      meRepositoryProvider.overrideWithValue(FakeMeRepository(meWith([(_gym, roles)]))),
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
    expect(find.text('Sesión de hoy'), findsOneWidget);

    await tester.tap(find.text('Planificación'));
    await tester.pumpAndSettle();

    expect(find.text('Temporizadores del club'), findsOneWidget);
    expect(find.text('Sesión de hoy'), findsNothing);
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

      expect(find.text('Sesión de hoy'), findsOneWidget);
      expect(find.text('Planificación'), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('an athlete is sent back to training when opening planning by URL', (tester) async {
      await _montar(tester, const Size(400, 800), roles: {Rol.atleta}, ruta: Rutas.planificacion);

      expect(find.text('Sesión de hoy'), findsOneWidget);
      expect(find.text('Temporizadores del club'), findsNothing);
    });

    testWidgets('an athlete on a wide screen has no rail either', (tester) async {
      await _montar(tester, const Size(1200, 800), roles: {Rol.atleta});

      expect(find.byType(NavigationRail), findsNothing);
      expect(find.text('Planificación'), findsNothing);
    });

    testWidgets('a coach sees planning and can open it by URL', (tester) async {
      await _montar(tester, const Size(400, 800), ruta: Rutas.planificacion);

      expect(find.text('Temporizadores del club'), findsOneWidget);
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('Planificación')), findsOneWidget);
    });
  });
}
