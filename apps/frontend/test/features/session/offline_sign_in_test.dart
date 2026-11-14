import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/app/router.dart';
import 'package:maktub_frontend/app/session_redirect.dart';
import 'package:maktub_frontend/core/offline/local_copy.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart' show httpClientProvider;
import 'package:maktub_frontend/features/access/presentation/providers.dart';
import 'package:maktub_frontend/features/session/domain/session_manager.dart';
import 'package:maktub_frontend/features/session/presentation/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../access/fakes.dart';
import 'fakes.dart';

/// The app starting with the saved token, over the real API client; [online] says whether the network answers.
ProviderContainer _start(FakeTokenStore tokens, FakeAuthApi auth, {required bool online}) {
  final me = meWith([(club('c1', 'Gimnasio', TipoClub.club), {Rol.coach, Rol.atleta})], athleteIds: {'c1': 'ari'});
  final client = MockClient((request) async {
    if (!online) throw http.ClientException('Failed to fetch', request.url);
    expect(request.url.path, '/me');
    return http.Response(jsonEncode(me.toJson()), 200, headers: {'content-type': 'application/json'});
  });
  return ProviderContainer(
    overrides: [
      tokenStoreProvider.overrideWithValue(tokens),
      authApiProvider.overrideWithValue(auth),
      httpClientProvider.overrideWithValue(client),
    ],
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the saved token is enough to get in without signal: the session is not closed for lack of network', () async {
    final tokens = FakeTokenStore(issued(1));
    final auth = FakeAuthApi();
    final online = _start(tokens, auth, online: true);
    await online.read(sessionManagerProvider).restore();
    expect((await online.read(meProvider.future))?.athleteId, 'ari');
    online.dispose();

    final offline = _start(tokens, auth, online: false);
    addTearDown(offline.dispose);
    await offline.read(sessionManagerProvider).restore();
    final me = await offline.read(meProvider.future);

    expect(offline.read(sessionControllerProvider), SessionStatus.signedIn);
    expect(me?.athleteId, 'ari');
    expect(me?.activeClub?.club.id, 'c1');
    expect(offline.read(hasAthleteProfileProvider), isTrue);
    expect(offline.read(canPlanProvider), isTrue);
    expect(tokens.saved, isNotNull);
    expect(auth.refreshCalls, isEmpty);
    expect(auth.logoutCalls, isEmpty);
    expect(sessionRedirect(SessionStatus.signedIn, Uri.parse(Rutas.entrenamiento)), isNull);
  });

  test('without signal and without a saved copy, GET /me fails but the session stays open', () async {
    final tokens = FakeTokenStore(issued(1));
    final offline = _start(tokens, FakeAuthApi(), online: false);
    addTearDown(offline.dispose);
    await offline.read(sessionManagerProvider).restore();

    await expectLater(offline.read(meRepositoryProvider).fetch(), throwsA(isA<NoLocalCopy>()));
    expect(offline.read(sessionControllerProvider), SessionStatus.signedIn);
    expect(tokens.saved, isNotNull);
  });
}
