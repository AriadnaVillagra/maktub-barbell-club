import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _Contexto extends Mock implements RequestContext {}

void main() {
  RequestContext contexto(HttpMethod metodo, String? origen) {
    final c = _Contexto();
    when(() => c.request).thenReturn(Request(
      metodo.value,
      Uri.parse('http://localhost/x'),
      headers: {'origin': ?origen},
    ));
    return c;
  }

  Future<Response> correr(Middleware m, Handler h, [HttpMethod metodo = HttpMethod.get, String? origen]) async =>
      m(h)(contexto(metodo, origen));

  group('manejarErrores', () {
    test('ErrorDeSolicitud se vuelve su estado con {error}', () async {
      final r = await correr(manejarErrores(), (_) => throw const ErrorDeSolicitud.noEncontrado('no está'));
      expect(r.statusCode, HttpStatus.notFound);
      expect(await r.json(), {'error': 'no está'});
    });

    test('FormatException es un 400', () async {
      final r = await correr(manejarErrores(), (_) => throw const FormatException('mal'));
      expect(r.statusCode, HttpStatus.badRequest);
    });

    test('cualquier otro error es un 500 sin detalles', () async {
      final r = await correr(manejarErrores(), (_) => throw StateError('secreto interno'));
      expect(r.statusCode, HttpStatus.internalServerError);
      expect('${await r.json()}', isNot(contains('secreto')));
    });
  });

  group('cors', () {
    const pages = 'https://usuario.github.io';
    final middleware = cors(origenes: [pages]);

    test('responde el preflight de un origen permitido sin llamar al handler', () async {
      var llamado = false;
      final r = await correr(middleware, (_) {
        llamado = true;
        return Response();
      }, HttpMethod.options, pages);
      expect(r.statusCode, HttpStatus.noContent);
      expect(r.headers['access-control-allow-origin'], pages);
      expect(r.headers['access-control-allow-headers'], contains('Authorization'));
      expect(llamado, isFalse);
    });

    test('no habilita orígenes que no están en la lista', () async {
      final r = await correr(middleware, (_) => Response(body: 'ok'), HttpMethod.get, 'https://otro.github.io');
      expect(r.headers.containsKey('access-control-allow-origin'), isFalse);
      expect(r.headers['vary'], 'Origin');
    });

    test('permite localhost en cualquier puerto para desarrollo', () async {
      final r = await correr(middleware, (_) => Response(body: 'ok'), HttpMethod.get, 'http://localhost:53172');
      expect(r.headers['access-control-allow-origin'], 'http://localhost:53172');
    });

    test('nunca usa comodín ni credenciales', () async {
      final r = await correr(middleware, (_) => Response(body: 'ok'), HttpMethod.get, pages);
      expect(r.headers['access-control-allow-origin'], isNot('*'));
      expect(r.headers.containsKey('access-control-allow-credentials'), isFalse);
    });
  });
}
