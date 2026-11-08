import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/cliente_api.dart';
import '../domain/assignment_repository.dart';

class HttpAssignmentRepository implements AssignmentRepository {
  HttpAssignmentRepository(this._client);

  final ClienteApi _client;

  static String _club(String clubId) =>
      '/clubes/${Uri.encodeComponent(clubId)}';

  @override
  Future<List<AthleteGroup>> groups(String clubId) async => [
    for (final g in await _client.getList('${_club(clubId)}/grupos'))
      AthleteGroup.fromJson((g as Map).cast<String, dynamic>()),
  ];

  @override
  Future<List<Assignment>> assignments(String clubId, {String? groupId}) async {
    final query = groupId == null
        ? ''
        : '?grupoId=${Uri.encodeQueryComponent(groupId)}';
    return [
      for (final a in await _client.getList(
        '${_club(clubId)}/asignaciones$query',
      ))
        Assignment.fromJson((a as Map).cast<String, dynamic>()),
    ];
  }

  @override
  Future<Assignment> assign(
    String clubId, {
    required String planId,
    required String groupId,
    required DateTime startDate,
  }) async => Assignment.fromJson(
    await _client.post(
      '${_club(clubId)}/asignaciones',
      cuerpo: {
        'planId': planId,
        'grupoId': groupId,
        'fechaInicio': aIsoFecha(startDate),
      },
    ),
  );

  @override
  Future<Assignment> end(
    String clubId,
    String assignmentId, {
    DateTime? endDate,
  }) async => Assignment.fromJson(
    await _client.post(
      '${_club(clubId)}/asignaciones/${Uri.encodeComponent(assignmentId)}/terminar',
      cuerpo: endDate == null ? null : {'fechaFin': aIsoFecha(endDate)},
    ),
  );
}
