import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maktub_frontend/core/red/api_providers.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/session/domain/session_manager.dart';
import 'package:maktub_frontend/features/session/domain/session_repositories.dart';
import 'package:maktub_frontend/features/session/presentation/providers.dart';

import 'fakes.dart';

/// End to end through the providers: the repositories are replaced by overrides and the network by
/// a [MockClient] that only accepts the newest access token.
void main() {
  late FakeTokenStore store;
  late FakeAuthApi api;
  late List<String?> sentTokens;
  late int Function(http.Request) statusFor;
  late ProviderContainer container;

  setUp(() {
    store = FakeTokenStore(issued(1));
    api = FakeAuthApi();
    sentTokens = [];
    statusFor = (request) => request.headers['Authorization'] == 'Bearer access-2' ? 200 : 401;
    final client = MockClient((request) async {
      sentTokens.add(request.headers['Authorization']);
      final status = statusFor(request);
      return http.Response(jsonEncode(status == 200 ? {'ok': true} : {'error': 'No autorizado.'}), status);
    });
    container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(store),
        authApiProvider.overrideWithValue(api),
        httpClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
  });

  test('every request carries the access token in the Authorization header', () async {
    statusFor = (_) => 200;
    await container.read(clienteApiProvider).get('/me');
    expect(sentTokens, ['Bearer access-1']);
  });

  test('two simultaneous 401s trigger one refresh; both retry with the new token', () async {
    final apiClient = container.read(clienteApiProvider);

    final a = apiClient.get('/me');
    final b = apiClient.get('/clubes/c1/catalogo');
    await pumpEventQueue();
    expect(api.refreshCalls, ['refresh-1']);

    api.pendingRefreshes.single.complete(issued(2));

    expect(await Future.wait([a, b]), [
      {'ok': true},
      {'ok': true},
    ]);
    expect(api.refreshCalls, hasLength(1));
    expect(sentTokens, ['Bearer access-1', 'Bearer access-1', 'Bearer access-2', 'Bearer access-2']);
    expect(store.saved?.refreshToken, 'refresh-2');
  });

  test('a 403 does not trigger a refresh', () async {
    statusFor = (_) => 403;

    await expectLater(
      container.read(clienteApiProvider).get('/clubes/otro/catalogo'),
      throwsA(isA<ErrorDeApi>().having((e) => e.estado, 'estado', 403)),
    );
    expect(api.refreshCalls, isEmpty);
    expect(sentTokens, hasLength(1));
  });

  test('a rejected refresh clears the tokens and the session goes back to signed out', () async {
    final statuses = <SessionStatus>[];
    container.listen(sessionControllerProvider, (_, next) => statuses.add(next), fireImmediately: true);

    final request = container.read(clienteApiProvider).get('/me');
    await pumpEventQueue();
    api.pendingRefreshes.single.completeError(const SessionRejected());

    await expectLater(request, throwsA(isA<ErrorDeApi>().having((e) => e.estado, 'estado', 401)));
    expect(store.saved, isNull);
    expect(statuses.last, SessionStatus.signedOut);
  });

  test('the controller signs in and out through the session', () async {
    store.saved = null;
    final controller = container.read(sessionControllerProvider.notifier);
    await container.read(sessionManagerProvider).restore();
    expect(container.read(sessionControllerProvider), SessionStatus.signedOut);

    await controller.signInWithGoogle('google-id-token');
    expect(container.read(sessionControllerProvider), SessionStatus.signedIn);
    expect(store.saved?.accessToken, 'access-1');

    await controller.signOut();
    expect(container.read(sessionControllerProvider), SessionStatus.signedOut);
    expect(api.logoutCalls, ['refresh-1']);
    expect(store.saved, isNull);
  });
}
