import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/fechas_http.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'crear_store.dart';

/// `POST /clubes/{clubId}/asignaciones` body `{planId, grupoId, fechaInicio}` (`fechaInicio` as `yyyy-MM-dd`)
/// → 201 with the assignment (`Assignment.toJson()`): active, with no end date. Needs [Accion.planificar] (the
/// coach). The server sets `id`, `clubId`, `estado` and `auditoria`.
///
/// The plan must exist in the club **and have a published version** (the draft is not looked at): 404 if the plan
/// or the group is not in the club, 422 if the plan was never published. A group has at most one active
/// assignment (D14): if it already has one this is 409 `{error}` and nothing is written; the coach ends it
/// first (`.../terminar`) and then creates the new one. [store], [newId] and [now] are for tests.
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
  }) : _newId = newId ?? (() => ObjectId().oid),
       _now = now ?? DateTime.now;

  final CreateAssignmentStore _store;
  final String Function() _newId;
  final DateTime Function() _now;

  Future<Assignment> call(ClubContext club, Json body) async {
    final planId = _requiredId(body['planId'], 'planId');
    final groupId = _requiredId(body['grupoId'], 'grupoId');
    final startDate = fechaDeSolicitud(body['fechaInicio'], 'fechaInicio');

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
    if (!await _store.groupExists(club.clubId, groupId)) {
      throw const ErrorDeSolicitud.noEncontrado('Grupo no encontrado.');
    }

    final assignment = Assignment(
      id: _newId(),
      clubId: club.clubId,
      planId: planId,
      groupId: groupId,
      startDate: startDate,
      auditoria: Auditoria.nueva(club.userId, ahora: _now()),
    );
    if (!await _store.insert(assignment)) {
      throw const ErrorDeSolicitud(
        'El grupo ya tiene una asignación activa; terminala antes de crear otra.',
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
