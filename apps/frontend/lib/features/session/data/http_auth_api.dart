import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/cliente_api.dart';
import '../domain/session_repositories.dart';

/// [AuthApi] over HTTP. Takes a client without an access-token source: a 401 here must never
/// trigger another renewal.
class HttpAuthApi implements AuthApi {
  HttpAuthApi(this._client) : assert(_client.auth == null);

  final ClienteApi _client;

  @override
  Future<IssuedSession> signInWithGoogle(String idToken, {String? device}) async {
    final body = await _client.post('/auth/google', cuerpo: {'idToken': idToken, 'device': ?device});
    return IssuedSession.fromJson(body);
  }

  @override
  Future<IssuedSession> refresh(String refreshToken) async {
    try {
      return IssuedSession.fromJson(await _client.post('/auth/refresh', headers: _bearer(refreshToken)));
    } on ErrorDeApi catch (e) {
      if (e.estado == 401 || e.estado == 403) throw SessionRejected(e.mensaje);
      rethrow;
    }
  }

  @override
  Future<void> logout(String refreshToken) => _client.post('/auth/logout', headers: _bearer(refreshToken));

  static Map<String, String> _bearer(String token) => {'Authorization': 'Bearer $token'};
}
