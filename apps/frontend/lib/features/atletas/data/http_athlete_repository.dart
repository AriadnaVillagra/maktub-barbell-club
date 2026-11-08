import 'package:maktub_core/maktub_core.dart';

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

  String _athletePath(String clubId, String athleteId) =>
      '${_path(clubId)}/${Uri.encodeComponent(athleteId)}';

  @override
  Future<void> addReference(
    String clubId,
    String athleteId, {
    required String exerciseId,
    required double value,
    required DateTime date,
  }) async {
    await _client.post(
      '${_athletePath(clubId, athleteId)}/referencias',
      cuerpo: {'ejercicioId': exerciseId, 'valor': value, 'fecha': aIsoFecha(date)},
    );
  }

  @override
  Future<void> addFactor(
    String clubId,
    String athleteId, {
    required String exerciseId,
    required double percent,
    required DateTime date,
  }) async {
    await _client.post(
      '${_athletePath(clubId, athleteId)}/factores',
      cuerpo: {'ejercicioId': exerciseId, 'valor': percent, 'fecha': aIsoFecha(date)},
    );
  }

  @override
  Future<void> setFixedWeight(
    String clubId,
    String athleteId, {
    required String exerciseId,
    required double kg,
  }) async {
    await _client.put(
      '${_athletePath(clubId, athleteId)}/kilajes',
      {'ejercicioId': exerciseId, 'kilos': kg},
    );
  }
}
