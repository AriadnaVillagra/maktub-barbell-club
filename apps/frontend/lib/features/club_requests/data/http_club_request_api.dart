import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/cliente_api.dart';
import '../domain/club_request_repositories.dart';

/// [ClubRequestApi] over HTTP. Like the auth endpoints, it takes a client without an access-token source.
class HttpClubRequestApi implements ClubRequestApi {
  HttpClubRequestApi(this._client) : assert(_client.auth == null);

  final ClienteApi _client;

  @override
  Future<ClubRequest> send({
    required String idToken,
    required String clubName,
    required String requesterName,
    String? note,
  }) async {
    final body = await _client.post(
      '/auth/pedidos-club',
      cuerpo: {'idToken': idToken, 'nombreClub': clubName, 'nombre': requesterName, 'nota': ?note},
    );
    return ClubRequest.fromJson((body['pedido'] as Map).cast<String, dynamic>());
  }
}
