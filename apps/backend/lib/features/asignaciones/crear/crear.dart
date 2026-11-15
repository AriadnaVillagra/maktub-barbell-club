import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/fechas_http.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'crear_store.dart';

/// `POST /clubes/{clubId}/asignaciones` body `{planId, grupoId | atletaId, fechaInicio}` (`fechaInicio` as
/// `yyyy-MM-dd`) → 201 with the assignment (`Assignment.toJson()`): active, with no end date. Needs
/// [Accion.planificar] (the coach). The server sets `id`, `clubId`, `estado` and `auditoria`.
///
/// The owner is a group (`grupoId`) or one athlete (`atletaId`, E8.8), exactly one of the two (400 otherwise). The
/// plan must exist in the club **and have a published version** (the draft is not looked at): 404 if the plan, the
/// group or the athlete is not in the club, 422 if the plan was never published. An owner has at most one active
/// assignment (D14: one per group, one per athlete; an athlete's own plan lives alongside their group's): if it
/// already has one this is 409 `{error}` and nothing is written; the coach ends it first (`.../terminar`) and then
/// creates the new one. [store], [newId] and [now] are for tests.
Future<Response> createAssignmentEndpoint(
  RequestContext context, {
  CreateAssignmentStore? store,
  String Function()? newId,
  DateTime Function()? now,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.planificar);
  final body = await leerCuerpoJson(context.request);
  final assignment = await CreateAssignment(
    store ?? MongoCreateAssignmentStore(context.read<Db>()),
    newId: newId,
    now: now,
  )(club, body);
  return Response.json(
    statusCode: HttpStatus.created,
    body: assignment.toJson(),
  );
}

class CreateAssignment {
  CreateAssignment(
    this._store, {
    String Function()? newId,
    DateTime Function()? now,
    this._history = false,
  }) : _newId = newId ?? (() => ObjectId().oid),
       _now = now ?? DateTime.now;

  final CreateAssignmentStore _store;
  final String Function() _newId;
  final DateTime Function() _now;

  /// Loading history (the E8 importer): the body also takes `fechaFin` (not before `fechaInicio`) and the
  /// assignment is created already ended. An ended assignment never counts for D14, so the group may have an
  /// active one. The endpoint never sets it.
  final bool _history;

  Future<Assignment> call(ClubContext club, Json body) async {
    final planId = _requiredId(body['planId'], 'planId');
    final groupId = _optionalId(body['grupoId'], 'grupoId');
    final athleteId = _optionalId(body['atletaId'], 'atletaId');
    if ((groupId == null) == (athleteId == null)) {
      throw const ErrorDeSolicitud(
        'La asignación es de un grupo ("grupoId") o de un atleta ("atletaId"): uno de los dos.',
      );
    }
    final startDate = fechaDeSolicitud(body['fechaInicio'], 'fechaInicio');
    final endDate = _history && body['fechaFin'] != null
        ? fechaDeSolicitud(body['fechaFin'], 'fechaFin')
        : null;
    if (endDate != null && endDate.isBefore(startDate)) {
      throw const ErrorDeSolicitud(
        '"fechaFin" no puede ser anterior a la fecha de inicio.',
      );
    }

    final published = await _store.planIsPublished(club.clubId, planId);
    if (published == null) {
      throw const ErrorDeSolicitud.noEncontrado('Plan no encontrado.');
    }
    if (!published) {
      throw const ErrorDeSolicitud(
        'El plan no tiene una versión publicada; publicalo antes de asignarlo.',
        estado: HttpStatus.unprocessableEntity,
      );
    }
    if (groupId != null && !await _store.groupExists(club.clubId, groupId)) {
      throw const ErrorDeSolicitud.noEncontrado('Grupo no encontrado.');
    }
    if (athleteId != null &&
        !await _store.athleteExists(club.clubId, athleteId)) {
      throw const ErrorDeSolicitud.noEncontrado('Atleta no encontrado.');
    }

    final assignment = Assignment(
      id: _newId(),
      clubId: club.clubId,
      planId: planId,
      groupId: groupId,
      athleteId: athleteId,
      startDate: startDate,
      status: endDate == null
          ? AssignmentStatus.active
          : AssignmentStatus.ended,
      endDate: endDate,
      auditoria: Auditoria.nueva(club.userId, ahora: _now()),
    );
    if (!await _store.insert(assignment)) {
      throw ErrorDeSolicitud(
        '${athleteId == null ? 'El grupo' : 'El atleta'} ya tiene una asignación activa; '
        'terminala antes de crear otra.',
        estado: HttpStatus.conflict,
      );
    }
    return assignment;
  }
}

String _requiredId(Object? value, String field) {
  final id = value is String ? value.trim() : '';
  if (id.isEmpty) throw ErrorDeSolicitud('"$field" es obligatorio.');
  return id;
}

/// The id in [value], or null when it is absent or blank.
String? _optionalId(Object? value, String field) {
  if (value == null) return null;
  if (value is! String) throw ErrorDeSolicitud('"$field" debe ser un id.');
  final id = value.trim();
  return id.isEmpty ? null : id;
}
