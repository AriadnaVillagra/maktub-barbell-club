import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/temporizador/presentation/controllers/crono_controller.dart';
import 'package:maktub_frontend/features/temporizador/presentation/providers.dart';
import 'package:maktub_frontend/features/temporizador/presentation/widgets/crono_con_atras.dart';

import 'timer_fakes.dart';

const _rest = Temporizador(id: 'd', nombre: 'Descanso', tipo: TipoTemporizador.countdown, trabajoSeg: 60);

/// With a timer open, the phone's back closes it and stays on the screen (Ari, 2026-11-19).
void main() {
  late GoRouter router;
  late ProviderContainer container;
  late int stepsBack;

  Future<void> pump(WidgetTester tester, {required bool browser}) async {
    stepsBack = 0;
    container = ProviderContainer(overrides: [timerPlatformProvider.overrideWithValue(FakeTimerPlatform())]);
    addTearDown(container.dispose);
    Widget page(String name) => Scaffold(body: Text(name));
    router = GoRouter(
      initialLocation: '/a',
      routes: [
        ShellRoute(
          builder: (_, _, child) => CronoConAtras(
            enNavegador: browser,
            // Like the browser: one step back is the previous screen without the mark.
            volverAtras: () {
              stepsBack++;
              final uri = router.routeInformationProvider.value.uri;
              router.go(uri.path);
            },
            child: child,
          ),
          routes: [
            GoRoute(path: '/a', builder: (_, _) => page('A')),
            GoRoute(path: '/b', builder: (_, _) => page('B')),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();
  }

  CronoController crono() => container.read(cronoControllerProvider.notifier);
  bool open() => container.read(cronoControllerProvider) != null;
  Uri location() => router.routeInformationProvider.value.uri;

  testWidgets('in the browser, opening a timer adds a step; going back from it closes the timer on the same screen', (
    tester,
  ) async {
    await pump(tester, browser: true);

    crono().iniciar(_rest);
    await tester.pump();
    expect(location().toString(), '/a?crono=1');

    // The browser's back: the previous step, the same screen without the mark.
    router.go('/a');
    await tester.pump();

    expect(open(), isFalse);
    expect(find.text('A'), findsOneWidget);
    crono().detener();
  });

  testWidgets('closing the timer from its ✕ takes back the step it added', (tester) async {
    await pump(tester, browser: true);
    crono().iniciar(_rest);
    await tester.pump();

    crono().detener();
    await tester.pump();

    expect(stepsBack, 1);
    expect(location().toString(), '/a');
  });

  testWidgets('going to another screen with the timer open keeps it running', (tester) async {
    await pump(tester, browser: true);
    crono().iniciar(_rest);
    await tester.pump();

    router.go('/b');
    await tester.pump();

    expect(open(), isTrue);
    expect(find.text('B'), findsOneWidget);
    crono().detener();
    await tester.pump();
    expect(stepsBack, 0, reason: 'the step is no longer where the user is');
  });

  testWidgets("outside the browser, the system's back closes the timer and stays", (tester) async {
    await pump(tester, browser: false);
    router.go('/b');
    await tester.pumpAndSettle();
    crono().iniciar(_rest);
    await tester.pump();
    expect(location().toString(), '/b');

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(open(), isFalse);
    expect(find.text('B'), findsOneWidget);
  });
}
