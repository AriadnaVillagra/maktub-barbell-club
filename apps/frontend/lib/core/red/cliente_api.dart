import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// URL base de la API. Se cambia con `--dart-define=API_URL=http://...`.
/// En el emulador de Android, localhost del host es `http://10.0.2.2:8080`.
const urlApi = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8080');

class ErrorDeApi implements Exception {
  const ErrorDeApi(this.mensaje, {this.estado, this.cuerpo});

  final String mensaje;
  final int? estado;

  /// The whole JSON body of the error response when it was an object (for the extra keys next to
  /// `error`, such as a 422's `problemas`), else null.
  final Map<String, dynamic>? cuerpo;

  @override
  String toString() => mensaje;
}

/// Where the client gets the access token it sends in `Authorization`, and who renews it.
abstract interface class AccessTokenSource {
  /// The access token to send now, or null when there is no session.
  Future<String?> accessToken();

  /// Called when a request sent with [rejectedToken] answered 401. Returns true when there is a
  /// (possibly new) access token worth retrying with, false when the session is over.
  Future<bool> renewAfterUnauthorized(String rejectedToken);
}

/// Cliente HTTP delgado: JSON de ida y vuelta, errores de la API como [ErrorDeApi].
///
/// With an [auth] source, every request carries `Authorization: Bearer <accessToken>`, and a 401
/// asks the source to renew and retries once. Any other status (a 403 included) is returned as is.
class ClienteApi {
  ClienteApi({required this.base, http.Client? cliente, this.auth}) : _http = cliente ?? http.Client();

  final Uri base;
  final AccessTokenSource? auth;
  final http.Client _http;

  Future<Map<String, dynamic>> get(String ruta, {Map<String, String>? headers}) =>
      _enviar('GET', ruta, headers: headers);

  /// GET for endpoints whose body is a JSON array.
  Future<List<dynamic>> getList(String ruta, {Map<String, String>? headers}) async =>
      (await _enviarCrudo('GET', ruta, headers: headers) as List);

  Future<Map<String, dynamic>> put(String ruta, Object cuerpo, {Map<String, String>? headers}) =>
      _enviar('PUT', ruta, cuerpo: cuerpo, headers: headers);

  Future<Map<String, dynamic>> patch(String ruta, Object cuerpo, {Map<String, String>? headers}) =>
      _enviar('PATCH', ruta, cuerpo: cuerpo, headers: headers);

  Future<Map<String, dynamic>> delete(String ruta, {Map<String, String>? headers}) =>
      _enviar('DELETE', ruta, headers: headers);

  Future<Map<String, dynamic>> post(String ruta, {Object? cuerpo, Map<String, String>? headers}) =>
      _enviar('POST', ruta, cuerpo: cuerpo, headers: headers);

  Future<Map<String, dynamic>> _enviar(String metodo, String ruta, {Object? cuerpo, Map<String, String>? headers}) async =>
      (await _enviarCrudo(metodo, ruta, cuerpo: cuerpo, headers: headers) as Map).cast<String, dynamic>();

  Future<Object?> _enviarCrudo(String metodo, String ruta, {Object? cuerpo, Map<String, String>? headers}) async {
    final source = auth;
    final token = await source?.accessToken();
    var respuesta = await _pedir(metodo, ruta, cuerpo, headers, token);
    if (respuesta.statusCode == 401 && source != null && token != null) {
      if (await source.renewAfterUnauthorized(token)) {
        respuesta = await _pedir(metodo, ruta, cuerpo, headers, await source.accessToken());
      }
    }
    return _leer(respuesta);
  }

  Future<http.Response> _pedir(
    String metodo,
    String ruta,
    Object? cuerpo,
    Map<String, String>? headers,
    String? token,
  ) async {
    final pedido = http.Request(metodo, base.resolve(ruta));
    if (token != null) pedido.headers['Authorization'] = 'Bearer $token';
    if (headers != null) pedido.headers.addAll(headers);
    if (cuerpo != null) {
      pedido.headers['Content-Type'] = 'application/json';
      pedido.body = jsonEncode(cuerpo);
    }
    try {
      return await http.Response.fromStream(await _http.send(pedido));
    } on Exception catch (e) {
      throw ErrorDeApi('No se pudo conectar con el servidor ($e).');
    }
  }

  Object? _leer(http.Response respuesta) {
    final Object? cuerpo = respuesta.body.isEmpty ? <String, dynamic>{} : jsonDecode(utf8.decode(respuesta.bodyBytes));
    if (respuesta.statusCode >= 400) {
      final mensaje = cuerpo is Map && cuerpo['error'] != null ? '${cuerpo['error']}' : 'Error ${respuesta.statusCode}';
      throw ErrorDeApi(
        mensaje,
        estado: respuesta.statusCode,
        cuerpo: cuerpo is Map ? cuerpo.cast<String, dynamic>() : null,
      );
    }
    return cuerpo;
  }

  void cerrar() => _http.close();
}

/// The one `http.Client` of the app. Tests override it with a `MockClient`.
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});
