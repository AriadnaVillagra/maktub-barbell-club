import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/app/app.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/access/presentation/providers.dart';
import 'package:maktub_frontend/features/club_requests/domain/club_request_repositories.dart';
import 'package:maktub_frontend/features/club_requests/presentation/providers.dart';
import 'package:maktub_frontend/features/session/presentation/providers.dart';
import 'package:maktub_frontend/features/session/presentation/sign_in_controller.dart';
import 'package:maktub_frontend/features/session/presentation/sign_in_page.dart';

import '../access/fakes.dart';
import '../session/fakes.dart';

class _FakeClubRequestApi implements ClubRequestApi {
  final sent = <(String, String, String, String?)>[];
  Object? error;

  @override
  Future<ClubRequest> send({
    required String idToken,
    required String clubName,
    required String requesterName,
    String? note,
  }) async {
    sent.add((idToken, clubName, requesterName, note));
    if (error != null) throw error!;
    return ClubRequest(
      id: 'r1',
      email: 'lu@example.com',
      requesterName: requesterName,
      clubName: clubName,
      note: note,
      auditoria: Auditoria.nueva('lu@example.com', ahora: DateTime.utc(2026, 11, 21)),
    );
  }
}

ErrorDeApi _refused(String code, {int status = 403, String message = 'Rechazado.'}) =>
    ErrorDeApi(message, estado: status, cuerpo: {'error': message, 'codigo': code});

/// The sign-in screen when Google's account has no Maktub account: requesting a club and seeing where the
/// request stands, all without a session.
void main() {
  late FakeTokenStore store;
  late FakeAuthApi auth;
  late _FakeClubRequestApi requests;

  setUp(() {
    store = FakeTokenStore();
    auth = FakeAuthApi();
    requests = _FakeClubRequestApi();
  });

  Widget fakeGoogleButton({required ValueChanged<String> onIdToken, required ValueChanged<String> onError}) =>
      TextButton(onPressed: () => onIdToken('google-id-token'), child: const Text('Google'));

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tokenStoreProvider.overrideWithValue(store),
        authApiProvider.overrideWithValue(auth),
        clubRequestApiProvider.overrideWithValue(requests),
        meRepositoryProvider.overrideWithValue(
          FakeMeRepository(meWith([(club('c1', 'Barra Norte', TipoClub.club), {Rol.adminClub, Rol.coach, Rol.atleta})])),
        ),
        googleButtonProvider.overrideWithValue(fakeGoogleButton),
      ],
      child: const MaktubApp(),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> fillForm(WidgetTester tester, {String club = 'Barra Norte', String name = 'Lu', String note = ''}) async {
    await tester.enterText(find.byKey(const Key('club-request-club')), club);
    await tester.enterText(find.byKey(const Key('club-request-name')), name);
    if (note.isNotEmpty) await tester.enterText(find.byKey(const Key('club-request-note')), note);
    await tester.pump();
  }

  testWidgets('no account → request a club → the request is in review', (tester) async {
    const message = 'Este email no tiene una cuenta en Maktub. Pedile acceso a tu coach.';
    auth.signInError = _refused('sin_cuenta', message: message);
    await mount(tester);

    await tapAndSettle(tester, find.text('Google'));
    expect(find.text(message), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const Key('club-request-open')));

    expect(find.text('Pedir un club'), findsOneWidget);
    final send = find.byKey(const Key('club-request-send'));
    expect(tester.widget<FilledButton>(send).onPressed, isNull, reason: 'nothing typed yet');

    await fillForm(tester, club: ' Barra Norte ', name: 'Lu', note: 'Somos 8');
    await tapAndSettle(tester, send);

    expect(requests.sent, [('google-id-token', 'Barra Norte', 'Lu', 'Somos 8')]);
    expect(find.text('Tu pedido está en revisión'), findsOneWidget);
    expect(store.saved, isNull, reason: 'a request opens no session');

    // Back to sign-in: Google's button is there again.
    await tapAndSettle(tester, find.byKey(const Key('club-request-back')));
    expect(find.text('Google'), findsOneWidget);
  });

  testWidgets('signing in with a pending request shows that it is in review', (tester) async {
    auth.signInError = _refused('pedido_pendiente');
    await mount(tester);

    await tapAndSettle(tester, find.text('Google'));

    expect(find.text('Tu pedido está en revisión'), findsOneWidget);
    expect(find.byKey(const Key('club-request-open')), findsNothing);
  });

  testWidgets('a rejected request says so and allows another one', (tester) async {
    auth.signInError = _refused('pedido_rechazado');
    await mount(tester);

    await tapAndSettle(tester, find.text('Google'));
    expect(find.text('Tu pedido no fue aprobado'), findsOneWidget);

    await tapAndSettle(tester, find.byKey(const Key('club-request-again')));
    await fillForm(tester, club: 'Barra Sur');
    await tapAndSettle(tester, find.byKey(const Key('club-request-send')));

    expect(requests.sent.single.$2, 'Barra Sur');
    expect(find.text('Tu pedido está en revisión'), findsOneWidget);
  });

  testWidgets('an API error keeps the form and what was typed', (tester) async {
    auth.signInError = _refused('sin_cuenta');
    requests.error = const ErrorDeApi('El nombre del club puede tener hasta 60 caracteres.', estado: 400);
    await mount(tester);

    await tapAndSettle(tester, find.text('Google'));
    await tapAndSettle(tester, find.byKey(const Key('club-request-open')));
    await fillForm(tester);
    await tapAndSettle(tester, find.byKey(const Key('club-request-send')));

    expect(find.text('El nombre del club puede tener hasta 60 caracteres.'), findsOneWidget);
    expect(find.text('Barra Norte'), findsOneWidget);

    // A request already waiting (sent from another tab) just shows it.
    requests.error = _refused('pedido_pendiente', status: 409);
    await tapAndSettle(tester, find.byKey(const Key('club-request-send')));
    expect(find.text('Tu pedido está en revisión'), findsOneWidget);
  });

  testWidgets('an expired ID token sends the person back to Google', (tester) async {
    auth.signInError = _refused('sin_cuenta');
    requests.error = const ErrorDeApi('No se pudo verificar el ingreso con Google.', estado: 401);
    await mount(tester);

    await tapAndSettle(tester, find.text('Google'));
    await tapAndSettle(tester, find.byKey(const Key('club-request-open')));
    await fillForm(tester);
    await tapAndSettle(tester, find.byKey(const Key('club-request-send')));

    expect(find.text(SignInController.tokenExpired), findsOneWidget);
    expect(find.text('Google'), findsOneWidget);
    expect(find.byKey(const Key('club-request-open')), findsNothing);
  });

  testWidgets('once approved, signing in opens the app in the new club', (tester) async {
    auth.signInError = _refused('pedido_pendiente');
    await mount(tester);
    await tapAndSettle(tester, find.text('Google'));
    expect(find.text('Tu pedido está en revisión'), findsOneWidget);

    auth.signInError = null;
    await tapAndSettle(tester, find.byKey(const Key('club-request-back')));
    await tapAndSettle(tester, find.text('Google'));

    expect(find.byType(SignInPage), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
