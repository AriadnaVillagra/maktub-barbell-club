/// Assignment of a plan to a group of athletes, or to one athlete, from a start date (E6.1, E8.8; docs/diseno.md,
/// "Plan y asignación").
///
/// It is plan x owner x start date, with a status. The owner is a group (`grupoId`) or one athlete (`atletaId`),
/// exactly one of the two; a document without `atletaId` is a group's, as every assignment before E8.8 was. An
/// athlete's own plan lives alongside their group's (decided by Ari on 2026-11-15). At most one assignment per
/// owner is active (D14, one per group and one per athlete): the model does not keep that rule, the assign slice
/// (E6.3) does.
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
    this.groupId,
    this.athleteId,
    required this.startDate,
    this.status = AssignmentStatus.active,
    this.endDate,
    required this.auditoria,
  }) : assert(
         (groupId == null) != (athleteId == null),
         'An assignment belongs to a group or to an athlete, exactly one.',
       );

  final String id;
  @override
  final String clubId;
  final String planId;

  /// The group that does the plan; null when it is one athlete's ([athleteId]).
  final String? groupId;

  /// The one athlete that does the plan; null when it is a group's ([groupId]).
  final String? athleteId;

  /// Whether the plan is one athlete's own instead of a group's.
  bool get isForAthlete => athleteId != null;

  /// The athletes the plan runs for: [athleteId] alone, or the members of [groupId] as [groupMembers] reads them.
  Future<List<String>> athletes(
    Future<List<String>> Function(String groupId) groupMembers,
  ) async => athleteId != null ? [athleteId!] : groupMembers(groupId!);

  /// Calendar date (`DateTime.utc(y, m, d)`) the plan's first cycle starts on; travels as `yyyy-MM-dd`.
  final DateTime startDate;
  final AssignmentStatus status;

  /// Calendar date the coach ended it on; null while it has not ended.
  final DateTime? endDate;
  final Auditoria auditoria;

  factory Assignment.fromJson(Json j) {
    final groupId = j['grupoId'] as String?;
    final athleteId = j['atletaId'] as String?;
    if ((groupId == null) == (athleteId == null)) {
      throw FormatException(
        'Una asignación tiene "grupoId" o "atletaId", exactamente uno.',
        j,
      );
    }
    return Assignment(
      id: '${j['id']}',
      clubId: '${j['clubId']}',
      planId: '${j['planId']}',
      groupId: groupId,
      athleteId: athleteId,
      startDate: desdeIsoFecha('${j['fechaInicio']}'),
      status: AssignmentStatus.deCable(j['estado']),
      endDate: desdeIsoFechaOpcional(j['fechaFin']),
      auditoria: Auditoria.fromJson(
        (j['auditoria'] as Map).cast<String, dynamic>(),
      ),
    );
  }

  Json toJson() => {
    'id': id,
    'clubId': clubId,
    'planId': planId,
    ...sinNulos({'grupoId': groupId, 'atletaId': athleteId}),
    'fechaInicio': aIsoFecha(startDate),
    'estado': status.cable,
    ...sinNulos({'fechaFin': endDate == null ? null : aIsoFecha(endDate!)}),
    'auditoria': auditoria.toJson(),
  };
}
