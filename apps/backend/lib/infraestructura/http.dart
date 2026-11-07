import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

/// Error de la solicitud del cliente. El middleware lo convierte en un 4xx con `{error}`.
class ErrorDeSolicitud implements Exception {
  const ErrorDeSolicitud(this.mensaje, {this.estado = HttpStatus.badRequest});

  const ErrorDeSolicitud.noEncontrado(this.mensaje) : estado = HttpStatus.notFound;

  final String mensaje;
  final int estado;

  @override
  String toString() => 'ErrorDeSolicitud($estado): $mensaje';
}

Future<Map<String, dynamic>> leerCuerpoJson(Request request) async {
  final cuerpo = await request.json();
  if (cuerpo is! Map) throw const ErrorDeSolicitud('El cuerpo debe ser un objeto JSON.');
  return cuerpo.cast<String, dynamic>();
}

Response metodoNoPermitido() => Response(statusCode: HttpStatus.methodNotAllowed);

/// Errores conocidos → 4xx; cualquier otro → 500 sin filtrar detalles.
Middleware manejarErrores() => (handler) => (context) async {
      try {
        return await handler(context);
      } on ErrorDeSolicitud catch (e) {
        return Response.json(statusCode: e.estado, body: {'error': e.mensaje});
      } on FormatException catch (e) {
        return Response.json(statusCode: HttpStatus.badRequest, body: {'error': e.message});
      } catch (e, pila) {
        stderr.writeln('Error no controlado: $e\n$pila');
        return Response.json(
          statusCode: HttpStatus.internalServerError,
          body: {'error': 'Error interno del servidor.'},
        );
      }
    };

/// Orígenes que pueden llamar a la API desde el navegador: la PWA vive en otro sitio
/// (GitHub Pages) que la API. Se configura con `ORIGENES_PERMITIDOS`, separados por coma,
/// p. ej. `https://usuario.github.io`. `http://localhost:<cualquier puerto>` se permite
/// siempre, para desarrollo con `flutter run -d chrome`.
List<String> origenesDesdeEntorno() => [
      for (final o in (Platform.environment['ORIGENES_PERMITIDOS'] ?? '').split(','))
        if (o.trim().isNotEmpty) o.trim().replaceAll(RegExp(r'/+$'), ''),
    ];

bool _esLocal(String origen) => RegExp(r'^http://(localhost|127\.0\.0\.1)(:\d+)?$').hasMatch(origen);

/// CORS con lista de orígenes. La autenticación viaja en `Authorization` (no hay cookies),
/// así que no se envía `Allow-Credentials`.
Middleware cors({List<String>? origenes}) {
  final permitidos = (origenes ?? origenesDesdeEntorno()).toSet();

  Map<String, String> cabeceras(String? origen) => {
        'Vary': 'Origin',
        if (origen != null && (permitidos.contains(origen) || _esLocal(origen))) ...{
          'Access-Control-Allow-Origin': origen,
          'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization',
          'Access-Control-Max-Age': '600',
        },
      };

  return (handler) => (context) async {
        final propias = cabeceras(context.request.headers['origin']);
        if (context.request.method == HttpMethod.options) {
          return Response(statusCode: HttpStatus.noContent, headers: propias);
        }
        final respuesta = await handler(context);
        return respuesta.copyWith(headers: {...respuesta.headers, ...propias});
      };
}
