import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/cliente_api.dart';
import '../domain/athlete_adjustments.dart';
import '../domain/session_repository.dart';

class HttpSessionRepository implements SessionRepository {
  HttpSessionRepository(this._client);

  final ClienteApi _client;

  static String _sessions(String clubId) =>
      '/clubes/${Uri.encodeComponent(clubId)}/sesiones';

  @override
  Future<LiveSession> open(
    String clubId, {
    required String assignmentId,
    required DateTime date,
    required int week,
    required int day,
    required Set<String> presentAthleteIds,
  }) async {
    final j = await _client.post(
      _sessions(clubId),
      cuerpo: {
        'asignacionId': assignmentId,
        'fecha': aIsoFecha(date),
        'semana': week,
        'dia': day,
        'presentes': presentAthleteIds.toList(),
      },
    );
    return LiveSession(
      session: Session.fromJson((j['sesion'] as Map).cast<String, dynamic>()),
      records: [
        for (final r in (j['registros'] as List? ?? const []))
          SetRecord.fromJson((r as Map).cast<String, dynamic>()),
      ],
    );
  }

  @override
  Future<List<ProposedSet>> proposedLoads(
    String clubId,
    String sessionId,
    String athleteId,
    AthleteAdjustments adjustments,
  ) async {
    final query = [
      'ajuste=${adjustments.session}',
      for (final e in adjustments.exercises.entries)
        'ajusteEjercicio=${Uri.encodeQueryComponent('${e.key}:${e.value}')}',
    ].join('&');
    final j = await _client.get(
      '${_sessions(clubId)}/${Uri.encodeComponent(sessionId)}'
      '/atletas/${Uri.encodeComponent(athleteId)}/kilos-propuestos?$query',
    );
    return [
      for (final s in (j['series'] as List? ?? const []))
        ProposedSet.fromJson((s as Map).cast<String, dynamic>()),
    ];
  }
}
