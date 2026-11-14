import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/sesion/proposed_view.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'proposed_loads_store.dart';

/// `GET /clubes/{clubId}/sesiones/{sesionId}/atletas/{atletaId}/kilos-propuestos?ajuste=&ajusteEjercicio=` → 200
/// `{"sesionId", "atletaId", "series": [ProposedSet]}`: the kilos proposed for every set of that athlete in that
/// session, resolved the way recording the set resolves them (`proposedSetLoad`). Needs [Accion.registrar].
///
/// `ajuste` is the day's session-level adjustment (50..150, default 100); each `ajusteEjercicio=<exerciseId>:<value>`
/// overrides it for one exercise, as `effectiveAdjustment` does. The work factor only travels to whoever can edit
/// references, and the real percent never does: an athlete is not told their factor.
///
/// A coach can ask about any present athlete, an athlete only within their own group (in a personal club, only
/// about themselves). 400 if the adjustment is malformed, 403 for a personal club asking about someone else, 404
/// if the session is not in the club or is another group's for an athlete, 422 if the athlete is not present or
/// the plan has no published version. [store] is for tests.
Future<Response> proposedLoadsEndpoint(
  RequestContext context,
  String sessionId,
  String athleteId, {
  ProposedLoadsStore? store,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.registrar);
  final query = context.request.uri.queryParametersAll;
  final sets =
      await ProposedLoads(store ?? MongoProposedLoadsStore(context.read<Db>()))(
        club,
        sessionId,
        athleteId,
        sessionAdjustment: sessionAdjustmentParam(query['ajuste']),
        exerciseAdjustments: exerciseAdjustmentsParam(query['ajusteEjercicio']),
      );
  return Response.json(
    body: {
      'sesionId': sessionId,
      'atletaId': athleteId,
      'series': [for (final set in sets) proposedSetForViewer(set, club)],
    },
  );
}

class ProposedLoads {
  ProposedLoads(this._store);

  final ProposedLoadsStore _store;

  Future<List<ProposedSet>> call(
    ClubContext club,
    String sessionId,
    String athleteId, {
    required int? sessionAdjustment,
    required Map<String, int> exerciseAdjustments,
  }) async {
    final clubId = club.clubId;
    final session = await _store.session(clubId, sessionId);
    if (session == null) throw _sessionNotFound;
    if (!club.can(Accion.planificar)) {
      await _authorizeAthlete(club, session, athleteId);
    }
    if (!session.presentAthleteIds.contains(athleteId)) {
      throw _unprocessable('Ese atleta no está presente en la sesión.');
    }
    final published = await _store.publishedPlan(clubId, session.planId);
    if (published == null) {
      throw _unprocessable(
        'El plan de la sesión no tiene una versión publicada.',
      );
    }

    final blocks = dayBlocks(published, week: session.week, day: session.day);
    final exercises = await _store.exercises(clubId);
    final rmIds = rmExerciseIdsOf(blocks, exercises);
    final referenced = rmIds.values.whereType<String>().toSet();
    final fixedWeights = await _store.fixedWeights(
      clubId,
      athleteId,
      rmIds.keys.toSet(),
    );
    return proposedDaySets(
      blocks: blocks,
      exercises: exercises,
      athleteId: athleteId,
      on: session.date,
      references: await _store.references(clubId, athleteId, referenced),
      factors: await _store.workFactors(clubId, athleteId, referenced),
      fixedKg: {for (final w in fixedWeights.values) w.exerciseId: w.kg},
      equipo: await _store.equipment(clubId) ?? Equipo.estandarDe(clubId),
      sessionAdjustment: sessionAdjustment,
      exerciseAdjustments: exerciseAdjustments,
    );
  }

  Future<void> _authorizeAthlete(
    ClubContext club,
    Session session,
    String athleteId,
  ) async {
    final own = await _store.athleteIdOfUser(club.clubId, club.userId);
    final assignment = await _store.assignment(
      club.clubId,
      session.assignmentId,
    );
    final members = assignment == null
        ? const <String>[]
        : await _store.groupMemberIds(club.clubId, assignment.groupId);
    if (own == null || !members.contains(own)) throw _sessionNotFound;
    if (club.clubType == TipoClub.personal && own != athleteId) {
      throw forbiddenRole;
    }
  }
}

const _sessionNotFound = ErrorDeSolicitud.noEncontrado('Sesión no encontrada.');

ErrorDeSolicitud _unprocessable(String message) =>
    ErrorDeSolicitud(message, estado: HttpStatus.unprocessableEntity);
