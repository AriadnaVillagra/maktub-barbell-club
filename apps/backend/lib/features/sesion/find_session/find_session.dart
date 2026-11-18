import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/sesion/record_view.dart';
import 'package:maktub_backend/infraestructura/fechas_http.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'find_session_store.dart';

/// `GET /clubes/{clubId}/sesiones?asignacionId=&fecha=yyyy-MM-dd&dia=&semana=` → 200
/// `{"sesion": Session, "registros": [SetRecord]}` when the session of that day of the assignment on that date
/// exists, **204 without body** when it does not (E7.27). It never creates one: the session is born with its first
/// write, through the opening (`POST`).
///
/// The key is the opening's: `fecha` gives the cycle and the week, `semana` (1..4) replaces the week when the user
/// picked another one, `dia` is 1-based. Same access as opening: needs [Accion.registrar]; an athlete only sees
/// sessions of their own group's assignment or their own (E8.8), a coach of any of the club. Records are filtered for the viewer like the
/// opening does.
///
/// 400 if a parameter is missing or malformed, 404 if the assignment is not in the club, or is neither their group's
/// nor their own for an athlete. [store] is for tests.
Future<Response> findSessionEndpoint(
  RequestContext context, {
  FindSessionStore? store,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.registrar);
  final found = await FindSession(
    store ?? MongoFindSessionStore(context.read<Db>()),
  )(club, context.request.uri.queryParameters);
  if (found == null) return Response(statusCode: HttpStatus.noContent);
  return Response.json(
    body: {
      'sesion': found.session.toJson(),
      'registros': [for (final r in found.records) recordForViewer(r, club)],
    },
  );
}

class FindSession {
  FindSession(this._store);

  final FindSessionStore _store;

  Future<({Session session, List<SetRecord> records})?> call(
    ClubContext club,
    Map<String, String> query,
  ) async {
    final assignmentId = query['asignacionId']?.trim() ?? '';
    if (assignmentId.isEmpty) {
      throw const ErrorDeSolicitud('"asignacionId" es obligatorio.');
    }
    final date = fechaDeSolicitud(query['fecha'], 'fecha');
    final day = int.tryParse(query['dia'] ?? '');
    if (day == null || day < 1) {
      throw const ErrorDeSolicitud('"dia" debe ser un entero desde 1.');
    }
    final weekText = query['semana'];
    final chosenWeek = weekText == null ? null : int.tryParse(weekText);
    if (weekText != null &&
        (chosenWeek == null || chosenWeek < 1 || chosenWeek > planCycleWeeks)) {
      throw const ErrorDeSolicitud('"semana" debe estar entre 1 y 4.');
    }

    final assignment = await _store.assignment(club.clubId, assignmentId);
    if (assignment == null) throw _assignmentNotFound;
    if (!club.can(Accion.planificar)) {
      final members = assignment.athleteIds;
      final own = await _store.athleteIdOfUser(club.clubId, club.userId);
      if (own == null || !members.contains(own)) throw _assignmentNotFound;
    }

    final week =
        chosenWeek ??
        UbicacionEnCiclo.desdeFechas(
          inicio: assignment.startDate,
          fecha: date,
        ).semana;
    final session = await _store.session(
      club.clubId,
      assignmentId: assignment.id,
      date: date,
      week: week,
      day: day,
    );
    if (session == null) return null;
    return (
      session: session,
      records: await _store.records(club.clubId, session.id),
    );
  }
}

const _assignmentNotFound = ErrorDeSolicitud.noEncontrado(
  'Asignación no encontrada.',
);
