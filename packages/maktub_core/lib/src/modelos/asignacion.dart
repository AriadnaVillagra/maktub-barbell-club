/// Assignment of a plan to a list of athletes from a start date (E6.1, E8.8, E6.7; docs/diseno.md, "Plan y
/// asignación").
///
/// It is plan x athletes x start date, with a status. Who does the plan is a list of [AssignmentMember]s, each with
/// the dates they were in it: the coach adds or removes athletes at any time without ending the plan (E6.7, decided
/// by Ari on 2026-11-18), and someone who leaves keeps the days they were in. An athlete can be in any number of
/// active assignments at once, even two on the same day (no D14 any more).
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

/// One athlete's time in an assignment: from [from] to [to], both included; [to] is null while they are still in.
/// An athlete removed and added again has two members.
class AssignmentMember {
  const AssignmentMember({
    required this.athleteId,
    required this.from,
    this.to,
  });

  final String athleteId;

  /// Calendar date of the first day they are in; travels as `yyyy-MM-dd`.
  final DateTime from;

  /// Calendar date of the last day they are in; null while they are still in.
  final DateTime? to;

  bool get isCurrent => to == null;

  /// Whether [date] (a calendar date) falls in this period.
  bool covers(DateTime date) =>
      !date.isBefore(from) && (to == null || !date.isAfter(to!));

  factory AssignmentMember.fromJson(Json j) => AssignmentMember(
    athleteId: '${j['atletaId']}',
    from: desdeIsoFecha('${j['desde']}'),
    to: desdeIsoFechaOpcional(j['hasta']),
  );

  Json toJson() => {
    'atletaId': athleteId,
    'desde': aIsoFecha(from),
    ...sinNulos({'hasta': to == null ? null : aIsoFecha(to!)}),
  };
}

class Assignment implements DelClub {
  const Assignment({
    required this.id,
    required this.clubId,
    required this.planId,
    this.members = const [],
    this.groupId,
    required this.startDate,
    this.status = AssignmentStatus.active,
    this.endDate,
    required this.auditoria,
  });

  final String id;
  @override
  final String clubId;
  final String planId;

  /// Who does the plan, and when (E6.7). Never empty for an assignment made through the app.
  final List<AssignmentMember> members;

  /// The group the athletes came from, for assignments made before E6.7 (a group's then); null for newer ones.
  /// Nothing reads the members from it: they were copied into [members] when the server first started with E6.7.
  final String? groupId;

  /// Every athlete that is or was in the assignment, once each, in the order they joined.
  List<String> get athleteIds => [
    ...{for (final m in members) m.athleteId},
  ];

  /// The athletes still in the assignment (no end date on their membership).
  List<String> get currentAthleteIds => [
    ...{
      for (final m in members)
        if (m.isCurrent) m.athleteId,
    },
  ];

  /// The athletes in the assignment on [date] (a calendar date).
  List<String> athleteIdsOn(DateTime date) => [
    ...{
      for (final m in members)
        if (m.covers(date)) m.athleteId,
    },
  ];

  /// Whether [athleteId] is in the assignment on [date].
  bool hasAthleteOn(String athleteId, DateTime date) =>
      members.any((m) => m.athleteId == athleteId && m.covers(date));

  /// Calendar date (`DateTime.utc(y, m, d)`) the plan's first cycle starts on; travels as `yyyy-MM-dd`.
  final DateTime startDate;
  final AssignmentStatus status;

  /// Calendar date the coach ended it on; null while it has not ended.
  final DateTime? endDate;
  final Auditoria auditoria;

  Assignment copyWith({
    List<AssignmentMember>? members,
    AssignmentStatus? status,
    DateTime? endDate,
    Auditoria? auditoria,
  }) => Assignment(
    id: id,
    clubId: clubId,
    planId: planId,
    members: members ?? this.members,
    groupId: groupId,
    startDate: startDate,
    status: status ?? this.status,
    endDate: endDate ?? this.endDate,
    auditoria: auditoria ?? this.auditoria,
  );

  /// Reads `atletas`; a document from before E6.7 without it but with `atletaId` (an athlete's own plan, E8.8)
  /// reads as that athlete alone from the start date, and one with only `grupoId` reads with no members until the
  /// server copies the group's into it (`asegurarIndices`).
  factory Assignment.fromJson(Json j) {
    final startDate = desdeIsoFecha('${j['fechaInicio']}');
    final endDate = desdeIsoFechaOpcional(j['fechaFin']);
    final raw = j['atletas'];
    final legacyAthlete = j['atletaId'] as String?;
    final members = raw is List
        ? [
            for (final m in raw)
              AssignmentMember.fromJson((m as Map).cast<String, dynamic>()),
          ]
        : [
            if (legacyAthlete != null)
              AssignmentMember(athleteId: legacyAthlete, from: startDate),
          ];
    return Assignment(
      id: '${j['id']}',
      clubId: '${j['clubId']}',
      planId: '${j['planId']}',
      members: members,
      groupId: j['grupoId'] as String?,
      startDate: startDate,
      status: AssignmentStatus.deCable(j['estado']),
      endDate: endDate,
      auditoria: Auditoria.fromJson(
        (j['auditoria'] as Map).cast<String, dynamic>(),
      ),
    );
  }

  Json toJson() => {
    'id': id,
    'clubId': clubId,
    'planId': planId,
    'atletas': [for (final m in members) m.toJson()],
    ...sinNulos({'grupoId': groupId}),
    'fechaInicio': aIsoFecha(startDate),
    'estado': status.cable,
    ...sinNulos({'fechaFin': endDate == null ? null : aIsoFecha(endDate!)}),
    'auditoria': auditoria.toJson(),
  };
}

/// The members of an assignment that starts on [startDate] after setting who is in it to [athleteIds] on [date]
/// (E6.7): someone who leaves stays until the day before [date]; someone who joins is in from [date], or from
/// [startDate] if the plan has not started yet. A period that would end before it starts is dropped, so adding and
/// removing someone before the plan starts leaves no trace. Who stays keeps their period as it was.
List<AssignmentMember> membersAfterChange(
  List<AssignmentMember> members, {
  required Iterable<String> athleteIds,
  required DateTime date,
  required DateTime startDate,
}) {
  final wanted = athleteIds.toSet();
  final effective = date.isBefore(startDate) ? startDate : date;
  final lastDay = effective.subtract(const Duration(days: 1));
  final current = <String>{};
  final result = <AssignmentMember>[];
  for (final m in members) {
    if (!m.isCurrent || wanted.contains(m.athleteId)) {
      result.add(m);
      if (m.isCurrent) current.add(m.athleteId);
      continue;
    }
    // Leaves: ends the day before, or disappears if it never got to start.
    if (!lastDay.isBefore(m.from)) {
      result.add(
        AssignmentMember(athleteId: m.athleteId, from: m.from, to: lastDay),
      );
    }
  }
  for (final id in wanted) {
    if (!current.contains(id)) {
      result.add(AssignmentMember(athleteId: id, from: effective));
    }
  }
  return result;
}
