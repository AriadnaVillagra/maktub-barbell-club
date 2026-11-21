import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/cliente_api.dart';
import '../domain/club_request_repositories.dart';

class HttpClubRequestsRepository implements ClubRequestsRepository {
  HttpClubRequestsRepository(this._client);

  final ClienteApi _client;

  static const _path = '/plataforma/pedidos-club';

  static String _action(String requestId, String action) => '$_path/${Uri.encodeComponent(requestId)}/$action';

  @override
  Future<List<ClubRequest>> pending() async {
    final json = await _client.get(_path);
    return [
      for (final r in (json['pedidos'] as List? ?? const [])) ClubRequest.fromJson((r as Map).cast<String, dynamic>()),
    ];
  }

  @override
  Future<Club> approve(String requestId) async {
    final json = await _client.post(_action(requestId, 'aprobar'));
    return Club.fromJson((json['club'] as Map).cast<String, dynamic>());
  }

  @override
  Future<void> reject(String requestId) => _client.post(_action(requestId, 'rechazar'));
}
