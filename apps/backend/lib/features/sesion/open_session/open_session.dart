import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/sesion/live_broadcast.dart';
import 'package:maktub_backend/features/sesion/record_view.dart';
import 'package:maktub_backend/infraestructura/fechas_http.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'open_session_store.dart';

/// `POST /clubes/{clubId}/sesiones` body `{asignacionId, fecha, dia, semana?, presentes?}` → 200
/// `{"sesion": Session, "registros": [SetRecord]}`: the session of that day of the assignment on that date, created
/// if there is none yet, with what was recorded so far. Needs [Accion.registrar].
///
/// - `fecha` (`yyyy-MM-dd`) gives the cycle and the week. `semana` (1..4) replaces the week when the user picked
///   another one in the calendar. `dia` (1-based) is chosen by the client, D13 included.
/// - `presentes` are athlete ids of the assignment's group; they add to the ones already present, so a device
///   never removes the athletes another one chose.
/// - An athlete can only open a session of their own group; a coach, of any group of the club.
///
/// Adding someone to `presentes` is published as a change of the session. [broadcast] is for tests, like the rest.
///
/// The plan is always read from its published version. 400 if the body is malformed, 404 if the assignment is not
/// in the club or is another group's for an athlete, 409 if it is not active, 422 if the plan has no published
/// version, the day is not in that week, or a present athlete is not in the group. [store], [newId] and [now] are
/// for tests.
Future<Response> openSessionEndpoint(
  RequestContext context, {
  OpenSessionStore? store,
  LiveBroadcast? broadcast,
  String Function()? newId,
  DateTime Function()? now,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.registrar);
  final body = await leerCuerpoJson(context.request);
  final opened = await OpenSession(
    store ?? MongoOpenSessionStore(context.read<Db>()),
    broadcast ?? context.read<LiveBroadcast>(),
    newId: newId,
    now: now,
  )(club, body);
  return Response.json(
    body: {
      'sesion': opened.session.toJson(),
      'registros': [for (final r in opened.records) recordForViewer(r, club)],
    },
  );
}

class OpenSession {
  OpenSession(
    this._store,
    this._broadcast, {
    String Function()? newId,
    DateTime Function()? now,
  }) : _newId = newId ?? (() => ObjectId().oid),
      _now = now ?? DateTime.now;

  final OpenSessionStore _store;
  final LiveBroadcast _broadcast;
  final String Function() _newId;
  final DateTime Function() _now;

  Future<({Session session, List<SetRecord> records})> call(
    ClubContext club,
    Json body,
  ) async {
    final assignmentId = body['asignacionId'] is String
        ? (body['asignacionId'] as String).trim()
        : '';
    if (assignmentId.isEmpty) {
      throw const ErrorDeSolicitud('"asignacionId" es obligatorio.');
    }
    final date = fechaDeSolicitud(body['fecha'], 'fecha');
    final day = _integer(body['dia']);
    if (day == null || day < 1) {
      throw const ErrorDeSolicitud('"dia" debe ser un entero desde 1.');
    }
    final chosenWeek = _integer(body['semana']);
    if (chosenWeek != null && (chosenWeek < 1 || chosenWeek > planCycleWeeks)) {
      throw const ErrorDeSolicitud('"semana" debe estar entre 1 y 4.');
    }
    final present = _presentIds(body['presentes']);

    final assignment = await _store.assignment(club.clubId, assignmentId);
    if (assignment == null) throw _assignmentNotFound;
    final members = await _store.groupMemberIds(
      club.clubId,
      assignment.groupId,
    );
    if (!club.can(Accion.planificar)) {
      final own = await _store.athleteIdOfUser(club.clubId, club.userId);
      if (own == null || !members.contains(own)) throw _assignmentNotFound;
    }
    if (assignment.status != AssignmentStatus.active) {
      throw const ErrorDeSolicitud(
        'La asignación no está activa.',
        estado: HttpStatus.conflict,
      );
    }
    if (!present.every(members.contains)) {
      throw const ErrorDeSolicitud(
        'Hay atletas presentes que no son del grupo de la asignación.',
        estado: HttpStatus.unprocessableEntity,
      );
    }

    final published = await _store.publishedPlan(
      club.clubId,
      assignment.planId,
    );
    if (published == null) {
      throw const ErrorDeSolicitud(
        'El plan de la asignación no tiene una versión publicada.',
        estado: HttpStatus.unprocessableEntity,
      );
    }
    final location = UbicacionEnCiclo.desdeFechas(
      inicio: assignment.startDate,
      fecha: date,
    );
    final week = chosenWeek ?? location.semana;
    final days = published.weekModelOf(week)?.days.length ?? 0;
    if (day > days) {
      throw const ErrorDeSolicitud(
        'Ese día no existe en esa semana del plan.',
        estado: HttpStatus.unprocessableEntity,
      );
    }

    final candidate = Session(
      id: _newId(),
      clubId: club.clubId,
      assignmentId: assignment.id,
      planId: assignment.planId,
      cycle: location.ciclo,
      week: week,
      day: day,
      date: date,
      presentAthleteIds: present,
      auditoria: Auditoria.nueva(club.userId, ahora: _now()),
    );
    final before = await _store.existing(candidate);
    var session = await _store.openOrResume(candidate);
    if (!{...?before?.presentAthleteIds}.containsAll(present)) {
      final id = session.id;
      session = await _broadcast.inOrder(id, () async {
        final changed = await _store.markChanged(club.clubId, id);
        _broadcast.publish(
          SessionChange.ofSession(changed.lastSessionChange, changed),
        );
        return changed;
      });
    }
    return (
      session: session,
      records: await _store.records(club.clubId, session.id),
    );
  }
}

const _assignmentNotFound = ErrorDeSolicitud.noEncontrado(
  'Asignación no encontrada.',
);

int? _integer(Object? value) =>
    value is num && value == value.roundToDouble() ? value.toInt() : null;

List<String> _presentIds(Object? value) {
  if (value == null) return const [];
  if (value is! List || value.any((id) => id is! String || id.isEmpty)) {
    throw const ErrorDeSolicitud(
      '"presentes" debe ser una lista de ids de atleta.',
    );
  }
  return value.cast<String>().toSet().toList();
}
