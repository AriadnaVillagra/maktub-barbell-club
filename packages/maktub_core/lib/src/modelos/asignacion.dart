/// Assignment of a plan to a group of athletes from a start date (E6.1; docs/diseno.md, "Plan y asignación").
///
/// It is plan x group x start date, with a status. Only the ids of the plan and the group travel here. At most
/// one assignment per group is active (D14): the model does not keep that rule, the assign slice (E6.3) does.
/// The plan repeats forever, so a cycle ending never ends an assignment: the coach does, by deactivating or
/// replacing it. Identifiers are English; the wire (JSON keys and enum values) stays Spanish.
library;

import 'base.dart';
import 'cable.dart';
import 'json.dart';
import '../reglas/fechas.dart';

/// Where an assignment stands. M1 only creates [active] ones and ends them; nothing pauses yet (F7, rest).
enum AssignmentStatus implements ConCable {
  active('activa'),

  /// While the group does a test plan (diseno, "Planes de test").
  paused('pausada'),
  ended('terminada');

  const AssignmentStatus(this.cable);
  @override
  final String cable;

  static AssignmentStatus deCable(Object? v) =>
      desdeCable(values, v, 'Estado de asignación');
}

class Assignment implements DelClub {
  const Assignment({
    required this.id,
    required this.clubId,
    required this.planId,
    required this.groupId,
    required this.startDate,
    this.status = AssignmentStatus.active,
    this.endDate,
    required this.auditoria,
  });

  final String id;
  @override
  final String clubId;
  final String planId;
  final String groupId;

  /// Calendar date (`DateTime.utc(y, m, d)`) the plan's first cycle starts on; travels as `yyyy-MM-dd`.
  final DateTime startDate;
  final AssignmentStatus status;

  /// Calendar date the coach ended it on; null while it has not ended.
  final DateTime? endDate;
  final Auditoria auditoria;

  factory Assignment.fromJson(Json j) => Assignment(
    id: '${j['id']}',
    clubId: '${j['clubId']}',
    planId: '${j['planId']}',
    groupId: '${j['grupoId']}',
    startDate: desdeIsoFecha('${j['fechaInicio']}'),
    status: AssignmentStatus.deCable(j['estado']),
    endDate: desdeIsoFechaOpcional(j['fechaFin']),
    auditoria: Auditoria.fromJson(
      (j['auditoria'] as Map).cast<String, dynamic>(),
    ),
  );

  Json toJson() => {
    'id': id,
    'clubId': clubId,
    'planId': planId,
    'grupoId': groupId,
    'fechaInicio': aIsoFecha(startDate),
    'estado': status.cable,
    ...sinNulos({'fechaFin': endDate == null ? null : aIsoFecha(endDate!)}),
    'auditoria': auditoria.toJson(),
  };
}
