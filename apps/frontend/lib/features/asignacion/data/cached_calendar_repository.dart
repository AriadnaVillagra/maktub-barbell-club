import 'package:maktub_core/maktub_core.dart';

import '../../../core/offline/local_copy.dart';
import '../domain/calendar_repository.dart';

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
    String groupId,
    DateTime from,
    DateTime to,
  ) => _reads.read(
    copyKey(['dayStates', clubId, groupId, aIsoFecha(from), aIsoFecha(to)]),
    () => _remote.dayStates(clubId, groupId, from, to),
    encode: (ss) => [
      for (final s in ss)
        {'ciclo': s.cycle, 'semana': s.week, 'dia': s.day, 'hecho': s.done},
    ],
    decode: (d) => [
      for (final s in (d as List).cast<Map>())
        DayState(
          cycle: (s['ciclo'] as num).toInt(),
          week: (s['semana'] as num).toInt(),
          day: (s['dia'] as num).toInt(),
          done: s['hecho'] == true,
        ),
    ],
  );
}

Json locationToJson(CalendarLocation l) => {
  'asignacionId': l.assignmentId,
  'planId': l.planId,
  'fechaInicio': aIsoFecha(l.startDate),
  'ciclo': l.cycle,
  'semana': l.week,
};

CalendarLocation locationFromJson(Json j) => CalendarLocation(
  assignmentId: '${j['asignacionId']}',
  planId: '${j['planId']}',
  startDate: DateTime.parse('${j['fechaInicio']}'),
  cycle: (j['ciclo'] as num).toInt(),
  week: (j['semana'] as num).toInt(),
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
