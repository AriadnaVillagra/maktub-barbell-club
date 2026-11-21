import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/sesion/day_status/day_status_store.dart';
import 'package:maktub_backend/infraestructura/fechas_http.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// Longest range a request may ask for, in days.
const maxDayStatusRange = 366;

/// `GET /clubes/{clubId}/grupos/{grupoId}/dias?desde=yyyy-MM-dd&hasta=yyyy-MM-dd[&atletaId=]` → the status of every
/// day of the group's active assignment in the cycles and weeks that the range touches (E7.13, D9). Needs
/// [Accion.verCatalogoYPlanes]. Responses (200):
///
/// - with an active assignment: `{"asignacion": {"id", "planId", "fechaInicio"}, "dias": [{"ciclo", "semana",
///   "dia", "estado", "fecha"?, "hechas"?, "total"?}]}`, ordered by cycle, week and day, with every day of the
///   week's model in the published plan.
/// - with none: `{"asignacion": null, "dias": []}`.
///
/// With `atletaId` (decision of Ari, 2026-11-21, which replaces D13's marking) each day carries that athlete's real
/// progress ([dayProgress]): `estado` is `hecho` when every planned set of the day is done, `en_curso` when some and
/// `pendiente` when none; `hechas` are the planned sets the athlete has done (a set done in two sessions of the same
/// day counts once, an estimated one counts like any other) and `total` the day's planned sets; `fecha` is the first
/// date with one of those sets done. Clients from before it never send `atletaId`, and read anything but `hecho` as
/// pending.
///
/// Without `atletaId`, as before: a day is `hecho` when any of its sessions has at least one set recorded as done by
/// anyone, else `pendiente`, without `hechas` nor `total`; `fecha` is the date of its first such session.
///
/// Nothing writes `AthleteDay` yet, so the status is derived from sessions and records. Recovered and missed (3.6)
/// are out of scope. 400 if a date is missing or malformed, `hasta` is before `desde` or the range is longer than
/// [maxDayStatusRange] days, 404 if the group is not in the club, 422 if the plan has no published version. [store]
/// is for tests.
Future<Response> dayStatusEndpoint(
  RequestContext context,
  String groupId, {
  DayStatusStore? store,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.verCatalogoYPlanes);
  final query = context.request.uri.queryParameters;
  final from = fechaDeSolicitud(query['desde'], 'desde');
  final to = fechaDeSolicitud(query['hasta'], 'hasta');
  final result = await ListDayStatus(
    store ?? MongoDayStatusStore(context.read<Db>()),
  )(club, groupId, from, to, athleteId: _athleteOf(query));
  return Response.json(body: result);
}

/// `GET /clubes/{clubId}/asignaciones/{asignacionId}/dias?desde=yyyy-MM-dd&hasta=yyyy-MM-dd[&atletaId=]` → the same
/// as the group's `.../dias`, for one assignment given by id, whoever it belongs to: a group's or one athlete's own
/// (E8.8, where an athlete can train two plans at once). Same responses and errors, except 404 when the assignment
/// is not in the club. The assignment is taken whatever its status. [store] is for tests.
Future<Response> assignmentDayStatusEndpoint(
  RequestContext context,
  String assignmentId, {
  DayStatusStore? store,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.verCatalogoYPlanes);
  final query = context.request.uri.queryParameters;
  final from = fechaDeSolicitud(query['desde'], 'desde');
  final to = fechaDeSolicitud(query['hasta'], 'hasta');
  final result = await ListDayStatus(
    store ?? MongoDayStatusStore(context.read<Db>()),
  ).ofAssignment(club, assignmentId, from, to, athleteId: _athleteOf(query));
  return Response.json(body: result);
}

String? _athleteOf(Map<String, String> query) {
  final id = query['atletaId']?.trim();
  return id == null || id.isEmpty ? null : id;
}

/// Where a day sits: cycle, week and day.
typedef _DayKey = (int, int, int);

/// The status fields of one day of the plan.
typedef _DayStatusOf = Json Function(_DayKey key, PlanDay day);

class ListDayStatus {
  ListDayStatus(this._store);

  final DayStatusStore _store;

  /// The days of the active assignment of [groupId]; with [athleteId], that athlete's progress in each.
  Future<Json> call(
    ClubContext club,
    String groupId,
    DateTime from,
    DateTime to, {
    String? athleteId,
  }) async {
    _checkRange(from, to);
    if (!await _store.groupExists(club.clubId, groupId)) {
      throw const ErrorDeSolicitud.noEncontrado('Grupo no encontrado.');
    }
    final assignment = await _store.activeAssignment(club.clubId, groupId);
    if (assignment == null) return {'asignacion': null, 'dias': <Json>[]};
    return _days(club, assignment, from, to, athleteId);
  }

  /// The days of the assignment [assignmentId], whoever it belongs to; with [athleteId], that athlete's progress.
  Future<Json> ofAssignment(
    ClubContext club,
    String assignmentId,
    DateTime from,
    DateTime to, {
    String? athleteId,
  }) async {
    _checkRange(from, to);
    final assignment = await _store.assignment(club.clubId, assignmentId);
    if (assignment == null) {
      throw const ErrorDeSolicitud.noEncontrado('Asignación no encontrada.');
    }
    return _days(club, assignment, from, to, athleteId);
  }

  void _checkRange(DateTime from, DateTime to) {
    if (to.isBefore(from)) {
      throw const ErrorDeSolicitud('"hasta" no puede ser anterior a "desde".');
    }
    if (to.difference(from).inDays >= maxDayStatusRange) {
      throw const ErrorDeSolicitud(
        'El rango no puede pasar de $maxDayStatusRange días.',
      );
    }
  }

  Future<Json> _days(
    ClubContext club,
    Assignment assignment,
    DateTime from,
    DateTime to,
    String? athleteId,
  ) async {
    final plan = await _store.publishedPlan(club.clubId, assignment.planId);
    if (plan == null) {
      throw const ErrorDeSolicitud(
        'El plan de la asignación no tiene una versión publicada.',
        estado: HttpStatus.unprocessableEntity,
      );
    }

    // The (cycle, week) pairs the range touches: one probe per week is enough, plus the last date.
    final weeks = <(int, int)>{};
    for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 7))) {
      weeks.add(_locate(assignment, d));
    }
    weeks.add(_locate(assignment, to));
    final ordered = weeks.toList()
      ..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
    final cycles = [for (final c in {for (final w in ordered) w.$1}) c];

    final statusOf = athleteId == null
        ? await _anyoneStatus(club.clubId, assignment.id, cycles)
        : await _athleteStatus(club.clubId, assignment.id, cycles, athleteId);

    return {
      'asignacion': {
        'id': assignment.id,
        'planId': assignment.planId,
        'fechaInicio': aIsoFecha(assignment.startDate),
      },
      'dias': [
        for (final (cycle, week) in ordered)
          for (final (i, planDay)
              in (plan.weekModelOf(week)?.days ?? const <PlanDay>[]).indexed)
            {
              'ciclo': cycle,
              'semana': week,
              'dia': i + 1,
              ...statusOf((cycle, week, i + 1), planDay),
            },
      ],
    };
  }

  /// Without an athlete, as D13 marked it: a day is done when any of its sessions has a set done by anyone.
  Future<_DayStatusOf> _anyoneStatus(
    String clubId,
    String assignmentId,
    List<int> cycles,
  ) async {
    final dates = <_DayKey, DateTime>{};
    for (final d in await _store.doneDays(clubId, assignmentId, cycles)) {
      final key = (d.cycle, d.week, d.day);
      final known = dates[key];
      if (known == null || d.date.isBefore(known)) dates[key] = d.date;
    }
    return (key, _) => {
      'estado': dates.containsKey(key) ? 'hecho' : 'pendiente',
      if (dates[key] case final date?) 'fecha': aIsoFecha(date),
    };
  }

  /// The athlete's real progress in each day: the planned sets done, out of the planned ones.
  Future<_DayStatusOf> _athleteStatus(
    String clubId,
    String assignmentId,
    List<int> cycles,
    String athleteId,
  ) async {
    final byDay = <_DayKey, List<DoneSet>>{};
    for (final s in await _store.doneSets(
      clubId,
      assignmentId,
      cycles,
      athleteId,
    )) {
      (byDay[(s.cycle, s.week, s.day)] ??= []).add(s);
    }
    return (key, planDay) {
      final done = byDay[key] ?? const <DoneSet>[];
      final progress = dayProgress(planDay, [for (final s in done) s.position]);
      // Only a set the published plan still has dates the day.
      final planned = plannedSetPositions(planDay);
      DateTime? first;
      for (final s in done) {
        if (planned.contains(s.position) &&
            (first == null || s.date.isBefore(first))) {
          first = s.date;
        }
      }
      return {
        'estado': progress.status.cable,
        if (first case final date?) 'fecha': aIsoFecha(date),
        'hechas': progress.done,
        'total': progress.total,
      };
    };
  }

  (int, int) _locate(Assignment assignment, DateTime date) {
    final l = UbicacionEnCiclo.desdeFechas(
      inicio: assignment.startDate,
      fecha: date,
    );
    return (l.ciclo, l.semana);
  }
}
