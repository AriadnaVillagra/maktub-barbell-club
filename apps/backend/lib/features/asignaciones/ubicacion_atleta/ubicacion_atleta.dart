import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/fechas_http.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'ubicacion_atleta_store.dart';

/// `GET /clubes/{clubId}/atletas/{athleteId}/ubicacion?fecha=yyyy-MM-dd` → where [fecha] falls in **every** active
/// assignment the athlete trains: those of their groups and their own (E8.8: an athlete's own plan lives alongside
/// their group's, so a date can fall in two plans). Needs [Accion.verCatalogoYPlanes]; an athlete may only ask
/// about themselves (404 for anyone else), a coach about any athlete of the club. Response (200):
///
/// `{"fecha": "yyyy-MM-dd", "ubicaciones": [{"asignacion": {"id", "planId", "fechaInicio", "grupoId" | "atletaId"},
/// "ciclo": 1.., "semana": 1..4}]}`, the groups' assignments first and then the athlete's own, each group by
/// `fechaInicio`. Empty `ubicaciones` when there is none. A date before `fechaInicio` is cycle 1, week 1, as in the
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

    final groupIds = await _store.groupIdsOf(club.clubId, athleteId);
    final active = [
      ...await _store.activeAssignments(
        club.clubId,
        groupIds: groupIds,
        athleteId: athleteId,
      ),
    ]..sort(_groupsFirstThenByStart);
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
                'atletaId': ?a.athleteId,
              },
              'ciclo': l.ciclo,
              'semana': l.semana,
            },
      ],
    };
  }
}

int _groupsFirstThenByStart(Assignment a, Assignment b) {
  if (a.isForAthlete != b.isForAthlete) return a.isForAthlete ? 1 : -1;
  final byStart = a.startDate.compareTo(b.startDate);
  return byStart != 0 ? byStart : a.id.compareTo(b.id);
}
