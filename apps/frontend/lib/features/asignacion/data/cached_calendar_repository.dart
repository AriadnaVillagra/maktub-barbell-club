import 'package:maktub_core/maktub_core.dart';

import '../../../core/offline/local_copy.dart';
import '../domain/calendar_repository.dart';
import 'http_calendar_repository.dart' show dayStateFromJson, dayStateToJson;

/// The calendar's reads with the device's copy (E7.15): where each date falls, the published plans and the days'
/// states. A date that was neither preloaded nor seen says so in its message.
class CachedCalendarRepository implements CalendarRepository {
  CachedCalendarRepository(this._remote, this._reads);

  final CalendarRepository _remote;
  final LocalCopyReads _reads;

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  @override
  Future<CalendarLocation?> locate(
    String clubId,
    String groupId,
    DateTime date,
  ) => _reads.read(
    copyKey(['locate', clubId, groupId, aIsoFecha(date)]),
    () => _remote.locate(clubId, groupId, date),
    encode: (l) => l == null ? null : locationToJson(l),
    decode: (d) =>
        d == null ? null : locationFromJson((d as Map).cast<String, dynamic>()),
    missing:
        'Sin señal y sin datos guardados del ${_date(date)}: '
        'no se precargó ni se abrió antes en este dispositivo. '
        'Se carga cuando vuelva la señal.',
  );

  @override
  Future<List<CalendarLocation>> locateAthlete(
    String clubId,
    String athleteId,
    DateTime date,
  ) => _reads.read(
    copyKey(['locateAthlete', clubId, athleteId, aIsoFecha(date)]),
    () => _remote.locateAthlete(clubId, athleteId, date),
    encode: (ls) => [for (final l in ls) locationToJson(l)],
    decode: (d) => [
      for (final l in d as List)
        locationFromJson((l as Map).cast<String, dynamic>()),
    ],
    missing:
        'Sin señal y sin datos guardados del ${_date(date)}: '
        'no se precargó ni se abrió antes en este dispositivo. '
        'Se carga cuando vuelva la señal.',
  );

  @override
  Future<PublishedPlanView> publishedPlan(String clubId, String planId) =>
      _reads.read(
        copyKey(['plan', clubId, planId]),
        () => _remote.publishedPlan(clubId, planId),
        encode: planToJson,
        decode: (d) => planFromJson((d as Map).cast<String, dynamic>()),
      );

  @override
  Future<List<DayState>> dayStates(
    String clubId,
    String assignmentId,
    DateTime from,
    DateTime to, {
    String? athleteId,
  }) => _reads.read(
    // Each athlete's progress is their own: the athlete is part of the key ('-' for anyone's, the old marking).
    copyKey([
      'assignmentDays',
      clubId,
      assignmentId,
      athleteId ?? '-',
      aIsoFecha(from),
      aIsoFecha(to),
    ]),
    () => _remote.dayStates(clubId, assignmentId, from, to, athleteId: athleteId),
    encode: (ss) => [for (final s in ss) dayStateToJson(s)],
    decode: (d) => [
      for (final s in (d as List).cast<Map>())
        dayStateFromJson(s.cast<String, dynamic>()),
    ],
  );
}

Json locationToJson(CalendarLocation l) => {
  'asignacionId': l.assignmentId,
  'planId': l.planId,
  'fechaInicio': aIsoFecha(l.startDate),
  'ciclo': l.cycle,
  'semana': l.week,
  'grupoId': ?l.groupId,
  'atletaId': ?l.athleteId,
  'atletas': ?l.athleteIds,
};

CalendarLocation locationFromJson(Json j) => CalendarLocation(
  assignmentId: '${j['asignacionId']}',
  planId: '${j['planId']}',
  startDate: DateTime.parse('${j['fechaInicio']}'),
  cycle: (j['ciclo'] as num).toInt(),
  week: (j['semana'] as num).toInt(),
  groupId: j['grupoId'] as String?,
  athleteId: j['atletaId'] as String?,
  athleteIds: (j['atletas'] as List?)?.map((e) => '$e').toList(),
);

Json planToJson(PublishedPlanView p) => {
  'id': p.id,
  'nombre': p.name,
  'tipo': p.type.cable,
  'modelosSemana': [for (final m in p.weekModels) m.toJson()],
  'asignacion': p.weekAssignment,
  'publicadoEn': p.publishedAt.toUtc().toIso8601String(),
};

PublishedPlanView planFromJson(Json j) => PublishedPlanView(
  id: '${j['id']}',
  name: '${j['nombre']}',
  type: PlanType.deCable(j['tipo']),
  weekModels: [
    for (final m in j['modelosSemana'] as List)
      WeekModel.fromJson((m as Map).cast<String, dynamic>()),
  ],
  weekAssignment: [for (final e in j['asignacion'] as List) '$e'],
  publishedAt: DateTime.parse('${j['publicadoEn']}').toUtc(),
);
