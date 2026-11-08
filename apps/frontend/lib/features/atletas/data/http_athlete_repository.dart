import '../../../core/red/cliente_api.dart';
import '../domain/athlete_repository.dart';

class HttpAthleteRepository implements AthleteRepository {
  HttpAthleteRepository(this._client);

  final ClienteApi _client;

  static String _path(String clubId) =>
      '/clubes/${Uri.encodeComponent(clubId)}/atletas';

  @override
  Future<List<AthleteSummary>> athletes(String clubId) async {
    final json = await _client.getList(_path(clubId));
    return [
      for (final a in json)
        AthleteSummary.fromJson((a as Map).cast<String, dynamic>()),
    ];
  }

  @override
  Future<AthleteSheet> sheet(String clubId, String athleteId) async =>
      AthleteSheet.fromJson(
        await _client.get('${_path(clubId)}/${Uri.encodeComponent(athleteId)}'),
      );
}
