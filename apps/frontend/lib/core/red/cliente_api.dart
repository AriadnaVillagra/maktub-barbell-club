import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// URL base de la API. Se cambia con `--dart-define=API_URL=http://...`.
/// En el emulador de Android, localhost del host es `http://10.0.2.2:8080`.
const urlApi = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8080');

class ErrorDeApi implements Exception {
  const ErrorDeApi(this.mensaje, {this.estado});

  final String mensaje;
  final int? estado;

  @override
  String toString() => mensaje;
}

/// Cliente HTTP delgado: JSON de ida y vuelta, errores de la API como [ErrorDeApi].
class ClienteApi {
  ClienteApi({required this.base, http.Client? cliente}) : _http = cliente ?? http.Client();

  final Uri base;
  final http.Client _http;

  Future<Map<String, dynamic>> get(String ruta) => _enviar(() => _http.get(base.resolve(ruta)));

  Future<Map<String, dynamic>> put(String ruta, Object cuerpo) => _enviar(
        () => _http.put(
          base.resolve(ruta),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(cuerpo),
        ),
      );

  Future<Map<String, dynamic>> _enviar(Future<http.Response> Function() pedido) async {
    final http.Response respuesta;
    try {
      respuesta = await pedido();
    } on Exception catch (e) {
      throw ErrorDeApi('No se pudo conectar con el servidor ($e).');
    }

    final cuerpo = respuesta.body.isEmpty ? <String, dynamic>{} : jsonDecode(utf8.decode(respuesta.bodyBytes));
    if (respuesta.statusCode >= 400) {
      final mensaje = cuerpo is Map && cuerpo['error'] != null ? '${cuerpo['error']}' : 'Error ${respuesta.statusCode}';
      throw ErrorDeApi(mensaje, estado: respuesta.statusCode);
    }
    return (cuerpo as Map).cast<String, dynamic>();
  }

  void cerrar() => _http.close();
}

final clienteApiProvider = Provider<ClienteApi>((ref) {
  final cliente = ClienteApi(base: Uri.parse(urlApi));
  ref.onDispose(cliente.cerrar);
  return cliente;
});
