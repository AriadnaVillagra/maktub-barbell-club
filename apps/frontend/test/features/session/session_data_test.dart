import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/session/data/http_auth_api.dart';
import 'package:maktub_frontend/features/session/data/shared_preferences_token_store.dart';
import 'package:maktub_frontend/features/session/domain/session_repositories.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  group('HttpAuthApi', () {
    late List<http.Request> requests;

    HttpAuthApi apiAnswering(int status, Object body) {
      requests = [];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response.bytes(utf8.encode(jsonEncode(body)), status);
      });
      return HttpAuthApi(ClienteApi(base: Uri.parse('http://api.test'), cliente: client));
    }

    test('signs in with the Google ID token and reads the issued session', () async {
      final api = apiAnswering(200, issued(1).toJson());

      final session = await api.signInWithGoogle('google-id-token', device: 'Pixel');

      expect(session.refreshToken, 'refresh-1');
      expect(requests.single.url.path, '/auth/google');
      expect(jsonDecode(requests.single.body), {'idToken': 'google-id-token', 'device': 'Pixel'});
      expect(requests.single.headers['Authorization'], isNull);
    });

    test('an unknown email surfaces the API message as a 403, not a rejected session', () async {
      final api = apiAnswering(403, {'error': 'Ese email no tiene cuenta.'});

      await expectLater(
        api.signInWithGoogle('google-id-token'),
        throwsA(isA<ErrorDeApi>()
            .having((e) => e.estado, 'estado', 403)
            .having((e) => e.mensaje, 'mensaje', 'Ese email no tiene cuenta.')),
      );
    });

    test('refreshes with the refresh token in the header', () async {
      final api = apiAnswering(200, issued(2).toJson());

      final session = await api.refresh('refresh-1');

      expect(session.accessToken, 'access-2');
      expect(requests.single.url.path, '/auth/refresh');
      expect(requests.single.method, 'POST');
      expect(requests.single.headers['Authorization'], 'Bearer refresh-1');
    });

    test('a 401 on refresh is a rejected session', () async {
      final api = apiAnswering(401, {'error': 'La sesión no es válida.'});
      await expectLater(api.refresh('refresh-1'), throwsA(isA<SessionRejected>()));
    });

    test('a 429 on refresh is not a rejected session', () async {
      final api = apiAnswering(429, {'error': 'Demasiados intentos.'});
      await expectLater(api.refresh('refresh-1'), throwsA(isA<ErrorDeApi>()));
    });

    test('logs out with the refresh token in the header', () async {
      requests = [];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response('', 204);
      });
      await HttpAuthApi(ClienteApi(base: Uri.parse('http://api.test'), cliente: client)).logout('refresh-1');

      expect(requests.single.url.path, '/auth/logout');
      expect(requests.single.headers['Authorization'], 'Bearer refresh-1');
    });
  });

  group('SharedPreferencesTokenStore', () {
    test('writes, reads and clears the tokens', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesTokenStore();

      expect(await store.read(), isNull);
      await store.write(issued(1));
      final read = await store.read();
      expect(read?.accessToken, 'access-1');
      expect(read?.refreshToken, 'refresh-1');
      expect(read?.accessTokenExpiresAt, issued(1).accessTokenExpiresAt);

      await store.clear();
      expect(await store.read(), isNull);
    });

    test('unreadable saved data counts as no session', () async {
      SharedPreferences.setMockInitialValues({SharedPreferencesTokenStore.key: 'not json'});
      expect(await SharedPreferencesTokenStore().read(), isNull);
    });
  });
}
