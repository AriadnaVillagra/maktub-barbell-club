import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/fechas_http.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'ubicacion_store.dart';

/// `GET /clubes/{clubId}/grupos/{grupoId}/ubicacion?fecha=yyyy-MM-dd` → where [fecha] falls in the group's active
/// assignment. Needs [Accion.verCatalogoYPlanes]. Responses (200):
///
/// - with an active assignment:
///   `{"fecha": "yyyy-MM-dd", "asignacion": {"id", "planId", "fechaInicio"}, "ciclo": 1.., "semana": 1..4}`;
///   a date before `fechaInicio` is cycle 1, week 1 (as `UbicacionEnCiclo` defines it).
/// - with none (never assigned, or the assignment ended): `{"fecha": "yyyy-MM-dd", "asignacion": null}`.
///
/// Only cycle and week: the day is not decided here (D13). 400 if `fecha` is missing or malformed, 404 if the
/// group is not in the club, 422 if the active assignment's plan has no published version (cannot happen through
/// the assign slice; the draft is never read). [store] is for tests.
Future<Response> groupLocationEndpoint(
  RequestContext context,
  String groupId, {
  LocationStore? store,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.verCatalogoYPlanes);
  final date = fechaDeSolicitud(
    context.request.uri.queryParameters['fecha'],
    'fecha',
  );
  final result = await GroupLocation(
    store ?? MongoLocationStore(context.read<Db>()),
  )(club, groupId, date);
  return Response.json(body: result);
}

class GroupLocation {
  GroupLocation(this._store);

  final LocationStore _store;

  Future<Json> call(ClubContext club, String groupId, DateTime date) async {
    if (!await _store.groupExists(club.clubId, groupId)) {
      throw const ErrorDeSolicitud.noEncontrado('Grupo no encontrado.');
    }
    final assignment = await _store.activeAssignment(club.clubId, groupId);
    if (assignment == null) {
      return {'fecha': aIsoFecha(date), 'asignacion': null};
    }
    if (!await _store.planIsPublished(club.clubId, assignment.planId)) {
      throw const ErrorDeSolicitud(
        'El plan de la asignación no tiene una versión publicada.',
        estado: HttpStatus.unprocessableEntity,
      );
    }
    final location = UbicacionEnCiclo.desdeFechas(
      inicio: assignment.startDate,
      fecha: date,
    );
    return {
      'fecha': aIsoFecha(date),
      'asignacion': {
        'id': assignment.id,
        'planId': assignment.planId,
        'fechaInicio': aIsoFecha(assignment.startDate),
      },
      'ciclo': location.ciclo,
      'semana': location.semana,
    };
  }
}
