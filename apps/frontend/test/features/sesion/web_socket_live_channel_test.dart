import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/sesion/data/web_socket_live_channel.dart';
import 'package:maktub_frontend/features/sesion/domain/set_write.dart';

import 'live_fakes.dart';

void main() {
  group('liveUri', () {
    test('uses ws for http and carries only the ticket', () {
      final uri = liveUri(
        Uri.parse('http://localhost:8080'),
        'c1',
        's 1',
        'abc',
      );

      expect(
        uri.toString(),
        'ws://localhost:8080/vivo/clubes/c1/sesiones/s%201?ticket=abc',
      );
    });

    test('uses wss for https', () {
      final uri = liveUri(
        Uri.parse('https://maktub-api.example.run.app'),
        'c1',
        's1',
        't',
      );

      expect(uri.scheme, 'wss');
      expect(uri.path, '/vivo/clubes/c1/sesiones/s1');
    });
  });

  test(
    'resyncs with the access token in the header and reads the changes',
    () async {
      final server = FakeLiveServer();
      final record = server.write(
        SetWrite.of(
          null,
          athleteId: 'ari',
          blockIndex: 0,
          prescriptionIndex: 0,
          setIndex: 0,
          adjustment: 0,
        ).markedDone(),
      );
      http.Request? sent;
      final client = ClienteApi(
        base: Uri.parse('http://localhost:8080'),
        cliente: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'secuencia': 4,
              'cambios': [
                {
                  'secuencia': 1,
                  'tipo': 'registro',
                  'registro': record.toJson(),
                },
              ],
            }),
            200,
          );
        }),
        auth: _Token(),
      );

      final page = await WebSocketLiveChannel(client)
          .changesSince('c1', 's1', 0);

      expect(sent!.url.path, '/clubes/c1/sesiones/s1/cambios');
      expect(sent!.url.queryParameters, {'desde': '0'});
      expect(sent!.headers['Authorization'], 'Bearer token');
      expect(page.last, 4);
      expect(page.changes.single.record!.athleteId, 'ari');
    },
  );

  test('asks the ticket with the token in the header and puts only the ticket in the URL', () async {
    http.Request? sent;
    Uri? opened;
    final client = ClienteApi(
      base: Uri.parse('https://api.example'),
      cliente: MockClient((request) async {
        sent = request;
        return http.Response(
          jsonEncode({
            'ticket': 'one-use',
            'expiresAt': '2026-11-18T10:00:00Z',
          }),
          200,
        );
      }),
      auth: _Token(),
    );
    final channel = WebSocketLiveChannel(
      client,
      open: (uri) {
        opened = uri;
        throw StateError('no socket in tests');
      },
    );

    await expectLater(channel.connect('c1', 's1'), throwsStateError);

    expect(sent!.method, 'POST');
    expect(sent!.url.path, '/clubes/c1/sesiones/s1/ticket');
    expect(sent!.headers['Authorization'], 'Bearer token');
    expect(
      opened.toString(),
      'wss://api.example/vivo/clubes/c1/sesiones/s1?ticket=one-use',
    );
    expect(opened.toString(), isNot(contains('token')));
  });
}

class _Token implements AccessTokenSource {
  @override
  Future<String?> accessToken() async => 'token';

  @override
  Future<bool> renewAfterUnauthorized(String rejectedToken) async => false;
}
