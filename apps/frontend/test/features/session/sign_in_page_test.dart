import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/app/app.dart';
import 'package:maktub_frontend/features/access/presentation/providers.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/session/presentation/providers.dart';
import 'package:maktub_frontend/features/session/presentation/sign_in_controller.dart';
import 'package:maktub_frontend/features/session/presentation/sign_in_page.dart';

import '../access/fakes.dart';
import 'fakes.dart';

/// The whole app with the repositories replaced and Google's button replaced by plain buttons: one
/// hands over an ID token as if the user had picked an account, the other reports a failure.
void main() {
  late FakeTokenStore store;
  late FakeAuthApi api;

  setUp(() {
    store = FakeTokenStore();
    api = FakeAuthApi();
  });

  Widget fakeGoogleButton({required ValueChanged<String> onIdToken, required ValueChanged<String> onError}) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(onPressed: () => onIdToken('google-id-token'), child: const Text('Google')),
          TextButton(onPressed: () => onError('Google no cargó.'), child: const Text('Falla')),
        ],
      );

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tokenStoreProvider.overrideWithValue(store),
        authApiProvider.overrideWithValue(api),
        meRepositoryProvider.overrideWithValue(
          FakeMeRepository(meWith([(club('c1', 'Gimnasio', TipoClub.club), {Rol.coach})])),
        ),
        googleButtonProvider.overrideWithValue(fakeGoogleButton),
      ],
      child: const MaktubApp(),
    ));
    await tester.pumpAndSettle();
  }

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(MaktubApp)));

  testWidgets('without a session it opens sign-in with Google’s button', (tester) async {
    await mount(tester);

    expect(find.byType(SignInPage), findsOneWidget);
    expect(find.text('Google'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('with a session it opens the shell', (tester) async {
    store.saved = issued(1);
    await mount(tester);

    expect(find.byType(SignInPage), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('picking an account sends the ID token to the API and opens the shell', (tester) async {
    await mount(tester);

    await tester.tap(find.text('Google'));
    await tester.pumpAndSettle();

    expect(api.signInCalls, ['google-id-token']);
    expect(store.saved?.refreshToken, 'refresh-1');
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(SignInPage), findsNothing);
  });

  testWidgets('an unknown email shows the API’s message and tries no refresh', (tester) async {
    const message = 'Este email no tiene una cuenta en Maktub. Pedile acceso a tu coach.';
    api.signInError = const ErrorDeApi(message, estado: 403);
    await mount(tester);

    await tester.tap(find.text('Google'));
    await tester.pumpAndSettle();

    expect(find.text(message), findsOneWidget);
    expect(find.byType(SignInPage), findsOneWidget);
    expect(api.refreshCalls, isEmpty);
    expect(store.saved, isNull);

    // The button is back, so another account can be tried.
    api.signInError = null;
    await tester.tap(find.text('Google'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('without signal it says so instead of the raw error', (tester) async {
    api.signInError = const ErrorDeApi('No se pudo conectar con el servidor (ClientException: x).');
    await mount(tester);

    await tester.tap(find.text('Google'));
    await tester.pumpAndSettle();

    expect(find.text(SignInController.noConnection), findsOneWidget);
  });

  testWidgets('a failure of Google’s button is shown', (tester) async {
    await mount(tester);

    await tester.tap(find.text('Falla'));
    await tester.pumpAndSettle();

    expect(find.text('Google no cargó.'), findsOneWidget);
  });

  testWidgets('signing out goes back to sign-in', (tester) async {
    store.saved = issued(1);
    await mount(tester);
    expect(find.byType(NavigationBar), findsOneWidget);

    await container(tester).read(sessionControllerProvider.notifier).signOut();
    await tester.pumpAndSettle();

    expect(api.logoutCalls, ['refresh-1']);
    expect(find.byType(SignInPage), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
