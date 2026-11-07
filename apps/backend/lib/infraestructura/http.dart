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

const _cabecerasCors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

/// Necesario para correr el frontend como Flutter web contra la API local.
Middleware cors() => (handler) => (context) async {
      if (context.request.method == HttpMethod.options) {
        return Response(statusCode: HttpStatus.noContent, headers: _cabecerasCors);
      }
      final respuesta = await handler(context);
      return respuesta.copyWith(headers: {...respuesta.headers, ..._cabecerasCors});
    };
