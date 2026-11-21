import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/fechas_http.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'crear_store.dart';

/// `POST /clubes/{clubId}/asignaciones` body `{planId, atletas: [atletaId…], fechaInicio}` (`fechaInicio` as
/// `yyyy-MM-dd`) → 201 with the assignment (`Assignment.toJson()`): active, with no end date, every athlete in from
/// the start date. Needs [Accion.planificar] (the coach). The server sets `id`, `clubId`, `estado` and `auditoria`.
///
/// Who does the plan is a list of athletes (E6.7), at least one, each of the club (404 otherwise). The body may
/// instead carry `grupoId` (the group's current members, and the group is kept on the assignment) or `atletaId`
/// (one athlete), as the E8 importer sends; exactly one of the three (400 otherwise). The plan must exist in the
/// club **and have a published version** (the draft is not looked at): 404 if not in the club, 422 if never
/// published. An athlete may be in any number of active assignments (E6.7 drops D14). [store], [newId] and [now]
/// are for tests.
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
  /// assignment is created already ended. The endpoint never sets it.
  final bool _history;

  Future<Assignment> call(ClubContext club, Json body) async {
    final planId = _requiredId(body['planId'], 'planId');
    final groupId = _optionalId(body['grupoId'], 'grupoId');
    final athleteId = _optionalId(body['atletaId'], 'atletaId');
    final listed = _ids(body['atletas']);
    if ([groupId, athleteId, listed].where((o) => o != null).length != 1) {
      throw const ErrorDeSolicitud(
        'La asignación lleva "atletas" (o "grupoId" o "atletaId"): uno de los tres.',
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

    // A plan the caller cannot see does not exist for them; one shared read-only can be assigned.
    final plan = await _store.plan(club.clubId, planId);
    if (plan == null || !club.planAccess(plan).see) {
      throw const ErrorDeSolicitud.noEncontrado('Plan no encontrado.');
    }
    if (plan.published == null) {
      throw const ErrorDeSolicitud(
        'El plan no tiene una versión publicada; publicalo antes de asignarlo.',
        estado: HttpStatus.unprocessableEntity,
      );
    }
    final List<String> athleteIds;
    if (groupId != null) {
      final members = await _store.groupMemberIds(club.clubId, groupId);
      if (members == null) {
        throw const ErrorDeSolicitud.noEncontrado('Grupo no encontrado.');
      }
      athleteIds = members;
    } else {
      athleteIds = listed ?? [athleteId!];
    }
    if (athleteIds.isEmpty) {
      throw const ErrorDeSolicitud('Elegí al menos un atleta.');
    }
    if (!await _store.athletesExist(club.clubId, athleteIds.toSet())) {
      throw const ErrorDeSolicitud.noEncontrado('Atleta no encontrado.');
    }

    final assignment = Assignment(
      id: _newId(),
      clubId: club.clubId,
      planId: planId,
      members: [
        for (final id in athleteIds)
          AssignmentMember(athleteId: id, from: startDate),
      ],
      groupId: groupId,
      startDate: startDate,
      status: endDate == null
          ? AssignmentStatus.active
          : AssignmentStatus.ended,
      endDate: endDate,
      auditoria: Auditoria.nueva(club.userId, ahora: _now()),
    );
    await _store.insert(assignment);
    return assignment;
  }
}

String _requiredId(Object? value, String field) {
  final id = value is String ? value.trim() : '';
  if (id.isEmpty) throw ErrorDeSolicitud('"$field" es obligatorio.');
  return id;
}

/// The distinct ids in [value], a list of ids, in order; null when it is absent.
List<String>? _ids(Object? value) {
  if (value == null) return null;
  const invalid = ErrorDeSolicitud('"atletas" debe ser una lista de ids.');
  if (value is! List) throw invalid;
  final ids = <String>{};
  for (final v in value) {
    final id = v is String ? v.trim() : '';
    if (id.isEmpty) throw invalid;
    ids.add(id);
  }
  return ids.toList();
}

/// The id in [value], or null when it is absent or blank.
String? _optionalId(Object? value, String field) {
  if (value == null) return null;
  if (value is! String) throw ErrorDeSolicitud('"$field" debe ser un id.');
  final id = value.trim();
  return id.isEmpty ? null : id;
}
