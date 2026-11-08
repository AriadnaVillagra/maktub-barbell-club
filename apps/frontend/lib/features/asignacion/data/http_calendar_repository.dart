import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/cliente_api.dart';
import '../domain/calendar_repository.dart';

class HttpCalendarRepository implements CalendarRepository {
  HttpCalendarRepository(this._client);

  final ClienteApi _client;

  static String _club(String clubId) =>
      '/clubes/${Uri.encodeComponent(clubId)}';

  @override
  Future<CalendarLocation?> locate(
    String clubId,
    String groupId,
    DateTime date,
  ) async {
    final j = await _client.get(
      '${_club(clubId)}/grupos/${Uri.encodeComponent(groupId)}/ubicacion'
      '?fecha=${aIsoFecha(date)}',
    );
    final assignment = j['asignacion'];
    if (assignment == null) return null;
    final a = (assignment as Map).cast<String, dynamic>();
    return CalendarLocation(
      assignmentId: '${a['id']}',
      planId: '${a['planId']}',
      startDate: DateTime.parse('${a['fechaInicio']}'),
      cycle: (j['ciclo'] as num).toInt(),
      week: (j['semana'] as num).toInt(),
    );
  }

  @override
  Future<PublishedPlanView> publishedPlan(String clubId, String planId) async {
    final j = await _client.get(
      '${_club(clubId)}/planes/${Uri.encodeComponent(planId)}/publicado',
    );
    return PublishedPlanView(
      id: '${j['id']}',
      name: '${j['nombre'] ?? ''}',
      type: j['tipo'] == null ? PlanType.regular : PlanType.deCable(j['tipo']),
      weekModels: [
        for (final m in (j['modelosSemana'] as List? ?? const []))
          WeekModel.fromJson((m as Map).cast<String, dynamic>()),
      ],
      weekAssignment: [
        for (final e in (j['asignacion'] as List? ?? const [])) '$e',
      ],
      publishedAt: DateTime.parse('${j['publicadoEn']}').toUtc(),
    );
  }
}
