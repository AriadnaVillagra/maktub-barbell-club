import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/cliente_api.dart';
import '../domain/all_clubs_repository.dart';

class HttpAllClubsRepository implements AllClubsRepository {
  HttpAllClubsRepository(this._client);

  final ClienteApi _client;

  @override
  Future<List<Club>> allClubs() async {
    final json = await _client.get('/plataforma/clubes');
    return [for (final c in (json['clubes'] as List? ?? const [])) Club.fromJson((c as Map).cast<String, dynamic>())];
  }
}
