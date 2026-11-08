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

/// `GET /clubes/{clubId}/grupos/{grupoId}/dias?desde=yyyy-MM-dd&hasta=yyyy-MM-dd` → the status of every day of the
/// group's active assignment in the cycles and weeks that the range touches (E7.13, D9, D13). Needs
/// [Accion.verCatalogoYPlanes]. Responses (200):
///
/// - with an active assignment: `{"asignacion": {"id", "planId", "fechaInicio"}, "dias": [{"ciclo", "semana",
///   "dia", "estado": "hecho" | "pendiente", "fecha"?}]}`, ordered by cycle, week and day, with every day of the
///   week's model in the published plan. `fecha` is the date of the session, only on done days.
/// - with none: `{"asignacion": null, "dias": []}`.
///
/// A day is done when its group session (D13: the group, not each athlete) has at least one set recorded as done;
/// otherwise it is pending. Nothing writes `AthleteDay` yet, so the status is derived from sessions and records.
/// Recovered and missed (3.6) are out of scope. 400 if a date is missing or malformed, `hasta` is before `desde` or
/// the range is longer than [maxDayStatusRange] days, 404 if the group is not in the club, 422 if the plan has no
/// published version. [store] is for tests.
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
  )(club, groupId, from, to);
  return Response.json(body: result);
}

class ListDayStatus {
  ListDayStatus(this._store);

  final DayStatusStore _store;

  Future<Json> call(
    ClubContext club,
    String groupId,
    DateTime from,
    DateTime to,
  ) async {
    if (to.isBefore(from)) {
      throw const ErrorDeSolicitud('"hasta" no puede ser anterior a "desde".');
    }
    if (to.difference(from).inDays >= maxDayStatusRange) {
      throw const ErrorDeSolicitud(
        'El rango no puede pasar de $maxDayStatusRange días.',
      );
    }
    if (!await _store.groupExists(club.clubId, groupId)) {
      throw const ErrorDeSolicitud.noEncontrado('Grupo no encontrado.');
    }
    final assignment = await _store.activeAssignment(club.clubId, groupId);
    if (assignment == null) return {'asignacion': null, 'dias': <Json>[]};
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

    final done = await _store.doneDays(club.clubId, assignment.id, [
      for (final c in {for (final w in ordered) w.$1}) c,
    ]);
    final doneDates = <(int, int, int), DateTime>{};
    for (final d in done) {
      final key = (d.cycle, d.week, d.day);
      final known = doneDates[key];
      if (known == null || d.date.isBefore(known)) doneDates[key] = d.date;
    }

    return {
      'asignacion': {
        'id': assignment.id,
        'planId': assignment.planId,
        'fechaInicio': aIsoFecha(assignment.startDate),
      },
      'dias': [
        for (final (cycle, week) in ordered)
          for (
            var day = 1;
            day <= (plan.weekModelOf(week)?.days.length ?? 0);
            day++
          )
            {
              'ciclo': cycle,
              'semana': week,
              'dia': day,
              'estado': doneDates.containsKey((cycle, week, day))
                  ? 'hecho'
                  : 'pendiente',
              if (doneDates[(cycle, week, day)] case final date?)
                'fecha': aIsoFecha(date),
            },
      ],
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
