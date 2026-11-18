import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/fechas_http.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'set_athletes_store.dart';

/// `PUT /clubes/{clubId}/asignaciones/{asignacionId}/atletas` body `{atletas: [atletaId…], fecha?}` → 200 with the
/// assignment, whose athletes from [fecha] on are exactly `atletas` (E6.7). `fecha` (`yyyy-MM-dd`) defaults to
/// today (UTC). Someone removed stays in until the day before `fecha`, keeping the days they were in; someone added
/// is in from `fecha` (from the start date if the plan has not started). See [membersAfterChange].
///
/// Needs [Accion.planificar] (the coach). 400 if `atletas` is not a non-empty list of ids (to leave nobody, end the
/// assignment instead); 404 if the assignment or an athlete is not in the club; 409 if the assignment is ended, or
/// if it changed since it was read (retry). [store] and [now] are for tests.
Future<Response> setAssignmentAthletesEndpoint(
  RequestContext context,
  String assignmentId, {
  SetAssignmentAthletesStore? store,
  DateTime Function()? now,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.planificar);
  final body = await leerCuerpoJson(context.request);
  final assignment = await SetAssignmentAthletes(
    store ?? MongoSetAssignmentAthletesStore(context.read<Db>()),
    now: now,
  )(club, assignmentId, body);
  return Response.json(body: assignment.toJson());
}

class SetAssignmentAthletes {
  SetAssignmentAthletes(this._store, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final SetAssignmentAthletesStore _store;
  final DateTime Function() _now;

  Future<Assignment> call(
    ClubContext club,
    String assignmentId,
    Json body,
  ) async {
    final athleteIds = _ids(body['atletas']);
    final at = _now().toUtc();
    final date = body['fecha'] == null
        ? soloFecha(at)
        : fechaDeSolicitud(body['fecha'], 'fecha');

    final current = await _store.assignment(club.clubId, assignmentId);
    if (current == null) {
      throw const ErrorDeSolicitud.noEncontrado('Asignación no encontrada.');
    }
    if (current.status == AssignmentStatus.ended) {
      throw const ErrorDeSolicitud(
        'La asignación está terminada.',
        estado: HttpStatus.conflict,
      );
    }
    if (!await _store.athletesExist(club.clubId, athleteIds.toSet())) {
      throw const ErrorDeSolicitud.noEncontrado('Atleta no encontrado.');
    }

    final members = membersAfterChange(
      current.members,
      athleteIds: athleteIds,
      date: date,
      startDate: current.startDate,
    );
    final written = await _store.replaceMembers(
      current,
      members,
      userId: club.userId,
      at: at,
    );
    if (!written) {
      throw const ErrorDeSolicitud(
        'La asignación cambió mientras tanto; volvé a intentarlo.',
        estado: HttpStatus.conflict,
      );
    }
    return current.copyWith(
      members: members,
      auditoria: current.auditoria.modificada(club.userId, ahora: at),
    );
  }
}

List<String> _ids(Object? value) {
  const invalid = ErrorDeSolicitud(
    '"atletas" debe ser una lista de ids con al menos uno.',
  );
  if (value is! List || value.isEmpty) throw invalid;
  final ids = <String>{};
  for (final v in value) {
    final id = v is String ? v.trim() : '';
    if (id.isEmpty) throw invalid;
    ids.add(id);
  }
  return ids.toList();
}
