import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/cliente_api.dart';
import '../domain/history_repository.dart';

/// `GET /clubes/{clubId}/atletas/{atletaId}/historial[?antesDe]` and `.../historial/{sesionId}`.
class HttpHistoryRepository implements HistoryRepository {
  HttpHistoryRepository(this._client);

  final ClienteApi _client;

  static String _path(String clubId, String athleteId) =>
      '/clubes/${Uri.encodeComponent(clubId)}/atletas/${Uri.encodeComponent(athleteId)}/historial';

  @override
  Future<HistoryPage> page(
    String clubId,
    String athleteId, {
    DateTime? before,
  }) async {
    final query = before == null ? '' : '?antesDe=${aIsoFecha(before)}';
    return HistoryPage.fromJson(
      await _client.get('${_path(clubId, athleteId)}$query'),
    );
  }

  @override
  Future<SessionHistory> session(
    String clubId,
    String athleteId,
    String sessionId,
  ) async => SessionHistory.fromJson(
    await _client.get(
      '${_path(clubId, athleteId)}/${Uri.encodeComponent(sessionId)}',
    ),
  );
}
