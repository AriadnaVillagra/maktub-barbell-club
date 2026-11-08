import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';

class _Source implements AccessTokenSource {
  _Source(this.token, {this.renewTo});

  String? token;
  final String? renewTo;
  final renewals = <String>[];

  @override
  Future<String?> accessToken() async => token;

  @override
  Future<bool> renewAfterUnauthorized(String rejectedToken) async {
    renewals.add(rejectedToken);
    if (renewTo == null) return false;
    token = renewTo;
    return true;
  }
}

void main() {
  late List<http.Request> requests;

  ClienteApi client(List<int> statuses, {AccessTokenSource? auth}) {
    requests = [];
    final queue = [...statuses];
    return ClienteApi(
      base: Uri.parse('http://api.test'),
      auth: auth,
      cliente: MockClient((request) async {
        requests.add(request);
        final status = queue.removeAt(0);
        return http.Response(jsonEncode(status < 400 ? {'n': requests.length} : {'error': 'Error $status.'}), status);
      }),
    );
  }

  test('without a source no Authorization header is sent and a 401 is just an error', () async {
    await expectLater(client([401]).get('/me'), throwsA(isA<ErrorDeApi>().having((e) => e.estado, 'estado', 401)));
    expect(requests.single.headers['Authorization'], isNull);
  });

  test('a 401 renews once and retries with the new token', () async {
    final source = _Source('old', renewTo: 'new');
    final body = await client([401, 200], auth: source).put('/x', {'a': 1});

    expect(body, {'n': 2});
    expect(source.renewals, ['old']);
    expect(requests.map((r) => r.headers['Authorization']), ['Bearer old', 'Bearer new']);
    expect(jsonDecode(requests.last.body), {'a': 1});
  });

  test('a 401 after the retry is returned as an error, without renewing again', () async {
    final source = _Source('old', renewTo: 'new');
    await expectLater(client([401, 401], auth: source).get('/me'), throwsA(isA<ErrorDeApi>()));
    expect(source.renewals, hasLength(1));
  });

  test('when the session is over the 401 is returned without retrying', () async {
    final source = _Source('old');
    await expectLater(client([401], auth: source).get('/me'), throwsA(isA<ErrorDeApi>()));
    expect(requests, hasLength(1));
  });

  test('a 403 does not renew', () async {
    final source = _Source('old', renewTo: 'new');
    await expectLater(
      client([403], auth: source).get('/me'),
      throwsA(isA<ErrorDeApi>().having((e) => e.mensaje, 'mensaje', 'Error 403.')),
    );
    expect(source.renewals, isEmpty);
  });

  test('without a session the request goes out without the header and a 401 does not renew', () async {
    final source = _Source(null, renewTo: 'new');
    await expectLater(client([401], auth: source).get('/me'), throwsA(isA<ErrorDeApi>()));
    expect(requests.single.headers['Authorization'], isNull);
    expect(source.renewals, isEmpty);
  });

  test('getList reads a JSON array body and still raises the API error', () async {
    final api = ClienteApi(
      base: Uri.parse('http://api.test'),
      cliente: MockClient(
        (request) async => request.url.path == '/ok'
            ? http.Response(jsonEncode([{'id': 'a1'}]), 200)
            : http.Response(jsonEncode({'error': 'Sin permiso.'}), 403),
      ),
    );
    expect(await api.getList('/ok'), [{'id': 'a1'}]);
    await expectLater(api.getList('/no'), throwsA(isA<ErrorDeApi>().having((e) => e.mensaje, 'mensaje', 'Sin permiso.')));
  });
}
