import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/fechas_http.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'terminar_store.dart';

/// `POST /clubes/{clubId}/asignaciones/{asignacionId}/terminar` body `{fechaFin?}` (`yyyy-MM-dd`; the body may be
/// empty) → 200 with the assignment, now `terminada` with its `fechaFin`. Without `fechaFin` the end date is
/// today (UTC), or the start date if the assignment has not started yet. Needs [Accion.planificar] (the coach).
/// Nothing is deleted: the assignment stays, ended. 404 if it is not in the club; 409 if it is already ended;
/// 400 if `fechaFin` is not a date or is before the start date. [store] and [now] are for tests.
Future<Response> endAssignmentEndpoint(
  RequestContext context,
  String assignmentId, {
  EndAssignmentStore? store,
  DateTime Function()? now,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.planificar);
  final body = await _optionalBody(context.request);
  final assignment = await EndAssignment(
    store ?? MongoEndAssignmentStore(context.read<Db>()),
    now: now,
  )(club, assignmentId, body);
  return Response.json(body: assignment.toJson());
}

Future<Json> _optionalBody(Request request) async {
  final raw = await request.body();
  return raw.trim().isEmpty ? const {} : leerCuerpoJson(request);
}

class EndAssignment {
  EndAssignment(this._store, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final EndAssignmentStore _store;
  final DateTime Function() _now;

  Future<Assignment> call(
    ClubContext club,
    String assignmentId,
    Json body,
  ) async {
    final current = await _store.assignment(club.clubId, assignmentId);
    if (current == null) {
      throw const ErrorDeSolicitud.noEncontrado('Asignación no encontrada.');
    }
    if (current.status == AssignmentStatus.ended) {
      throw const ErrorDeSolicitud(
        'La asignación ya está terminada.',
        estado: HttpStatus.conflict,
      );
    }

    final at = _now().toUtc();
    final DateTime endDate;
    if (body['fechaFin'] == null) {
      final today = soloFecha(at);
      endDate = today.isBefore(current.startDate) ? current.startDate : today;
    } else {
      endDate = fechaDeSolicitud(body['fechaFin'], 'fechaFin');
      if (endDate.isBefore(current.startDate)) {
        throw const ErrorDeSolicitud(
          '"fechaFin" no puede ser anterior a la fecha de inicio.',
        );
      }
    }

    final written = await _store.end(
      club.clubId,
      current.id,
      endDate: endDate,
      userId: club.userId,
      at: at,
    );
    if (!written) {
      throw const ErrorDeSolicitud(
        'La asignación ya está terminada.',
        estado: HttpStatus.conflict,
      );
    }
    return Assignment(
      id: current.id,
      clubId: current.clubId,
      planId: current.planId,
      groupId: current.groupId,
      startDate: current.startDate,
      status: AssignmentStatus.ended,
      endDate: endDate,
      auditoria: current.auditoria.modificada(club.userId, ahora: at),
    );
  }
}
