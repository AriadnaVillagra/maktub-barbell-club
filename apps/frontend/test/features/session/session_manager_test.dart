import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/session/domain/session_manager.dart';
import 'package:maktub_frontend/features/session/domain/session_repositories.dart';

import 'fakes.dart';

void main() {
  late FakeTokenStore store;
  late FakeAuthApi api;
  late SessionManager manager;

  Future<SessionManager> signedIn() async {
    store = FakeTokenStore(issued(1));
    manager = SessionManager(store, api);
    await manager.restore();
    return manager;
  }

  setUp(() {
    api = FakeAuthApi();
  });

  test('restore loads the saved tokens', () async {
    await signedIn();
    expect(manager.status, SessionStatus.signedIn);
    expect(await manager.currentAccessToken(), 'access-1');
  });

  test('without saved tokens it is signed out', () async {
    manager = SessionManager(FakeTokenStore(), api);
    await manager.restore();
    expect(manager.status, SessionStatus.signedOut);
    expect(await manager.currentAccessToken(), isNull);
  });

  test('signing in saves the tokens', () async {
    store = FakeTokenStore();
    manager = SessionManager(store, api);
    await manager.restore();

    await manager.signInWithGoogle('google-id-token');

    expect(store.saved?.refreshToken, 'refresh-1');
    expect(manager.status, SessionStatus.signedIn);
    expect(await manager.currentAccessToken(), 'access-1');
  });

  test('a failed sign-in (unknown email) keeps it signed out and tries no refresh', () async {
    store = FakeTokenStore();
    manager = SessionManager(store, api);
    await manager.restore();
    api.signInError = const ErrorDeApi('Ese email no tiene cuenta.', estado: 403);

    await expectLater(manager.signInWithGoogle('google-id-token'), throwsA(isA<ErrorDeApi>()));

    expect(manager.status, SessionStatus.signedOut);
    expect(store.saved, isNull);
    expect(api.refreshCalls, isEmpty);
  });

  test('simultaneous 401s share one refresh and all get its result', () async {
    await signedIn();

    final a = manager.renewAfterUnauthorized('access-1');
    final b = manager.renewAfterUnauthorized('access-1');
    final c = manager.renewAfterUnauthorized('access-1');
    await pumpEventQueue();
    expect(api.refreshCalls, ['refresh-1']);

    api.pendingRefreshes.single.complete(issued(2));

    expect(await Future.wait([a, b, c]), [true, true, true]);
    expect(api.refreshCalls, hasLength(1));
    expect(await manager.currentAccessToken(), 'access-2');
    expect(store.saved?.refreshToken, 'refresh-2');
  });

  test('a late 401 for a token already replaced retries without refreshing again', () async {
    await signedIn();
    final first = manager.renewAfterUnauthorized('access-1');
    await pumpEventQueue();
    api.pendingRefreshes.single.complete(issued(2));
    await first;

    expect(await manager.renewAfterUnauthorized('access-1'), isTrue);
    expect(api.refreshCalls, hasLength(1));
  });

  test('a rejected refresh clears the tokens and signs out', () async {
    await signedIn();
    final statuses = <SessionStatus>[];
    manager.changes.listen(statuses.add);

    final a = manager.renewAfterUnauthorized('access-1');
    final b = manager.renewAfterUnauthorized('access-1');
    await pumpEventQueue();
    api.pendingRefreshes.single.completeError(const SessionRejected());

    expect(await Future.wait([a, b]), [false, false]);
    expect(store.saved, isNull);
    expect(manager.status, SessionStatus.signedOut);
    expect(statuses, [SessionStatus.signedOut]);
    expect(await manager.currentAccessToken(), isNull);
  });

  test('a refresh without signal keeps the session and lets the next 401 try again', () async {
    await signedIn();
    final a = manager.renewAfterUnauthorized('access-1');
    await pumpEventQueue();
    api.pendingRefreshes.single.completeError(const ErrorDeApi('No se pudo conectar con el servidor.'));

    await expectLater(a, throwsA(isA<ErrorDeApi>()));
    expect(store.saved?.refreshToken, 'refresh-1');
    expect(manager.status, SessionStatus.signedIn);

    final b = manager.renewAfterUnauthorized('access-1');
    await pumpEventQueue();
    expect(api.refreshCalls, hasLength(2));
    api.pendingRefreshes.last.complete(issued(2));
    expect(await b, isTrue);
  });

  test('signing out revokes the refresh token in the API and clears the tokens', () async {
    await signedIn();

    await manager.signOut();

    expect(api.logoutCalls, ['refresh-1']);
    expect(store.saved, isNull);
    expect(manager.status, SessionStatus.signedOut);
  });

  test('signing out during a refresh revokes the rotated refresh token', () async {
    await signedIn();
    final renewal = manager.renewAfterUnauthorized('access-1');
    await pumpEventQueue();

    final signOut = manager.signOut();
    await pumpEventQueue();
    expect(api.logoutCalls, isEmpty);
    api.pendingRefreshes.single.complete(issued(2));
    await Future.wait([renewal, signOut]);

    expect(api.logoutCalls, ['refresh-2']);
    expect(store.saved, isNull);
    expect(manager.status, SessionStatus.signedOut);
  });

  test('signing out without signal still clears the local tokens', () async {
    await signedIn();
    api.logoutError = const ErrorDeApi('No se pudo conectar con el servidor.');

    await manager.signOut();

    expect(store.saved, isNull);
    expect(manager.status, SessionStatus.signedOut);
  });

  test('after signing out a 401 does not refresh', () async {
    await signedIn();
    await manager.signOut();

    expect(await manager.renewAfterUnauthorized('access-1'), isFalse);
    expect(api.refreshCalls, isEmpty);
  });
}
