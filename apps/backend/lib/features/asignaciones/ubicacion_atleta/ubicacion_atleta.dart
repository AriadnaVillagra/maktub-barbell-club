import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/fechas_http.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'ubicacion_atleta_store.dart';

/// `GET /clubes/{clubId}/atletas/{athleteId}/ubicacion?fecha=yyyy-MM-dd` → where [fecha] falls in **every** active
/// assignment the athlete is in on that date (E6.7: an athlete can be in any number of plans at once, and is in
/// one only between the dates they were added and removed). Needs [Accion.verCatalogoYPlanes]; an athlete may only ask
/// about themselves (404 for anyone else), a coach about any athlete of the club. Response (200):
///
/// `{"fecha": "yyyy-MM-dd", "ubicaciones": [{"asignacion": {"id", "planId", "fechaInicio", "grupoId"?, "atletas"},
/// "ciclo": 1.., "semana": 1..4}]}`, by `fechaInicio` (ties by id). `atletas` are the athletes in it on [fecha]. Empty `ubicaciones` when there is none. A date before `fechaInicio` is cycle 1, week 1, as in the
/// group's location (E6.4); the day is not decided here (D13).
///
/// 400 if `fecha` is missing or malformed, 404 if the athlete is not in the club, 422 if an active assignment's plan
/// has no published version (cannot happen through the assign slice). [store] is for tests.
Future<Response> athleteLocationEndpoint(
  RequestContext context,
  String athleteId, {
  AthleteLocationStore? store,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.verCatalogoYPlanes);
  final date = fechaDeSolicitud(
    context.request.uri.queryParameters['fecha'],
    'fecha',
  );
  final result = await AthleteLocation(
    store ?? MongoAthleteLocationStore(context.read<Db>()),
  )(club, athleteId, date);
  return Response.json(body: result);
}

class AthleteLocation {
  AthleteLocation(this._store);

  final AthleteLocationStore _store;

  Future<Json> call(ClubContext club, String athleteId, DateTime date) async {
    const notFound = ErrorDeSolicitud.noEncontrado('Atleta no encontrado.');
    if (!await _store.athleteExists(club.clubId, athleteId)) throw notFound;
    if (!club.can(Accion.planificar) &&
        await _store.athleteIdOfUser(club.clubId, club.userId) != athleteId) {
      throw notFound;
    }

    final active = [
      for (final a in await _store.activeAssignments(club.clubId, athleteId))
        if (a.hasAthleteOn(athleteId, date)) a,
    ]..sort(_byStart);
    final published = await _store.publishedPlanIds(club.clubId, {
      for (final a in active) a.planId,
    });
    if (active.any((a) => !published.contains(a.planId))) {
      throw const ErrorDeSolicitud(
        'El plan de una asignación no tiene una versión publicada.',
        estado: HttpStatus.unprocessableEntity,
      );
    }

    return {
      'fecha': aIsoFecha(date),
      'ubicaciones': [
        for (final a in active)
          for (final l in [
            UbicacionEnCiclo.desdeFechas(inicio: a.startDate, fecha: date),
          ])
            {
              'asignacion': {
                'id': a.id,
                'planId': a.planId,
                'fechaInicio': aIsoFecha(a.startDate),
                'grupoId': ?a.groupId,
                'atletas': a.athleteIdsOn(date),
              },
              'ciclo': l.ciclo,
              'semana': l.semana,
            },
      ],
    };
  }
}

int _byStart(Assignment a, Assignment b) {
  final byStart = a.startDate.compareTo(b.startDate);
  return byStart != 0 ? byStart : a.id.compareTo(b.id);
}
