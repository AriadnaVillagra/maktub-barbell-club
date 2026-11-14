import 'dart:async';
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
///
/// A request that gets no answer in time fails like one without connection (an [ErrorDeApi] without status), so a
/// slow network falls back to the device's copy (E7.15) instead of hanging the screen. Reads wait [readTimeout];
/// writes wait [writeTimeout], longer, because the queue of set writes has its own, shorter limit (E7.9) and other
/// writes are typed by hand and better not given up early. Any call can pass its own.
class ClienteApi {
  ClienteApi({
    required this.base,
    http.Client? cliente,
    this.auth,
    this.readTimeout = defaultReadTimeout,
    this.writeTimeout = defaultWriteTimeout,
  }) : _http = cliente ?? http.Client();

  /// Covers a cold start of the service (1–2 s) with room to spare.
  static const defaultReadTimeout = Duration(seconds: 8);
  static const defaultWriteTimeout = Duration(seconds: 30);

  final Uri base;
  final AccessTokenSource? auth;
  final Duration readTimeout;
  final Duration writeTimeout;
  final http.Client _http;

  Future<Map<String, dynamic>> get(String ruta, {Map<String, String>? headers, Duration? timeout}) =>
      _enviar('GET', ruta, headers: headers, timeout: timeout ?? readTimeout);

  /// GET for endpoints whose body is a JSON array.
  Future<List<dynamic>> getList(String ruta, {Map<String, String>? headers, Duration? timeout}) async =>
      (await _enviarCrudo('GET', ruta, headers: headers, timeout: timeout ?? readTimeout) as List);

  Future<Map<String, dynamic>> put(String ruta, Object cuerpo, {Map<String, String>? headers, Duration? timeout}) =>
      _enviar('PUT', ruta, cuerpo: cuerpo, headers: headers, timeout: timeout ?? writeTimeout);

  Future<Map<String, dynamic>> patch(String ruta, Object cuerpo, {Map<String, String>? headers, Duration? timeout}) =>
      _enviar('PATCH', ruta, cuerpo: cuerpo, headers: headers, timeout: timeout ?? writeTimeout);

  Future<Map<String, dynamic>> delete(String ruta, {Map<String, String>? headers, Duration? timeout}) =>
      _enviar('DELETE', ruta, headers: headers, timeout: timeout ?? writeTimeout);

  Future<Map<String, dynamic>> post(String ruta, {Object? cuerpo, Map<String, String>? headers, Duration? timeout}) =>
      _enviar('POST', ruta, cuerpo: cuerpo, headers: headers, timeout: timeout ?? writeTimeout);

  Future<Map<String, dynamic>> _enviar(
    String metodo,
    String ruta, {
    Object? cuerpo,
    Map<String, String>? headers,
    required Duration timeout,
  }) async =>
      (await _enviarCrudo(metodo, ruta, cuerpo: cuerpo, headers: headers, timeout: timeout) as Map)
          .cast<String, dynamic>();

  Future<Object?> _enviarCrudo(
    String metodo,
    String ruta, {
    Object? cuerpo,
    Map<String, String>? headers,
    required Duration timeout,
  }) async {
    final source = auth;
    final token = await source?.accessToken();
    var respuesta = await _pedir(metodo, ruta, cuerpo, headers, token, timeout);
    if (respuesta.statusCode == 401 && source != null && token != null) {
      if (await source.renewAfterUnauthorized(token)) {
        respuesta = await _pedir(metodo, ruta, cuerpo, headers, await source.accessToken(), timeout);
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
    Duration timeout,
  ) async {
    final pedido = http.Request(metodo, base.resolve(ruta));
    if (token != null) pedido.headers['Authorization'] = 'Bearer $token';
    if (headers != null) pedido.headers.addAll(headers);
    if (cuerpo != null) {
      pedido.headers['Content-Type'] = 'application/json';
      pedido.body = jsonEncode(cuerpo);
    }
    try {
      return await _http.send(pedido).then(http.Response.fromStream).timeout(timeout);
    } on TimeoutException {
      throw const ErrorDeApi('El servidor no respondió a tiempo.');
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
