import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
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
  final sets = await ProposedLoads(
    store ?? MongoProposedLoadsStore(context.read<Db>()),
  )(
    club,
    sessionId,
    athleteId,
    sessionAdjustment: _sessionAdjustment(query['ajuste']),
    exerciseAdjustments: _exerciseAdjustments(query['ajusteEjercicio']),
  );
  final showFactor = club.can(Accion.editarReferencias);
  return Response.json(
    body: {
      'sesionId': sessionId,
      'atletaId': athleteId,
      'series': [
        for (final set in sets)
          showFactor ? set.toJson() : (set.toJson()..remove('factor')),
      ],
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
      throw _unprocessable('El plan de la sesión no tiene una versión publicada.');
    }

    final days = published.weekModelOf(session.week)?.days ?? const <PlanDay>[];
    final blocks = session.day <= days.length
        ? days[session.day - 1].blocks
        : const <PlanBlock>[];

    final exercises = await _store.exercises(clubId);
    final dayExercises = <String, Exercise>{};
    for (final block in blocks) {
      for (final p in block.prescriptions) {
        final exercise = exercises[p.exerciseId];
        if (exercise != null) dayExercises[exercise.id] = exercise;
      }
    }
    final rmIds = <String, String?>{
      for (final e in dayExercises.entries)
        e.key: rmExerciseIdFor(e.value, exercises),
    };
    final referenced = rmIds.values.whereType<String>().toSet();
    final references = await _store.references(clubId, athleteId, referenced);
    final factors = await _store.workFactors(clubId, athleteId, referenced);
    final fixedWeights = await _store.fixedWeights(
      clubId,
      athleteId,
      dayExercises.keys.toSet(),
    );
    final equipo = await _store.equipment(clubId) ?? Equipo.estandarDe(clubId);

    return [
      for (var b = 0; b < blocks.length; b++)
        for (var p = 0; p < blocks[b].prescriptions.length; p++)
          for (var s = 0; s < blocks[b].prescriptions[p].sets.length; s++)
            if (blocks[b].prescriptions[p].exerciseId case final exerciseId?)
              _propose(
                position: (block: b, prescription: p, set: s),
                exerciseId: exerciseId,
                exercise: dayExercises[exerciseId],
                prescription: blocks[b].prescriptions[p],
                session: session,
                athleteId: athleteId,
                rmExerciseId: rmIds[exerciseId],
                references: references,
                factors: factors,
                fixedKg: fixedWeights[exerciseId]?.kg,
                equipo: equipo,
                adjustment: effectiveAdjustment(
                  session: sessionAdjustment,
                  exercise: exerciseAdjustments[exerciseId],
                ),
              ),
    ];
  }

  ProposedSet _propose({
    required ({int block, int prescription, int set}) position,
    required String exerciseId,
    required Exercise? exercise,
    required Prescription prescription,
    required Session session,
    required String athleteId,
    required String? rmExerciseId,
    required List<Reference> references,
    required List<WorkFactor> factors,
    required double? fixedKg,
    required Equipo equipo,
    required int adjustment,
  }) {
    final target = prescription.sets[position.set];
    if (exercise == null) {
      return ProposedSet(
        blockIndex: position.block,
        prescriptionIndex: position.prescription,
        setIndex: position.set,
        exerciseId: exerciseId,
      );
    }
    final basis = setLoadBasis(
      rmExerciseId: rmExerciseId,
      pct: target.pct,
      athleteId: athleteId,
      on: session.date,
      references: references,
      factors: factors,
    );
    final load = proposedSetLoad(
      basis: basis,
      target: target,
      adjustment: adjustment,
      athleteFixedKg: fixedKg,
      equipo: equipo,
      barKg: prescription.barKg ?? exercise.barKg,
    );
    final showsFactor =
        load.pcts != null && basis.workFactor != defaultWorkFactor;
    return ProposedSet(
      blockIndex: position.block,
      prescriptionIndex: position.prescription,
      setIndex: position.set,
      exerciseId: exerciseId,
      kg: load.kg,
      appliedPct: load.appliedPct,
      workFactor: showsFactor ? basis.workFactor : null,
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

int? _sessionAdjustment(List<String>? values) {
  if (values == null || values.isEmpty) return null;
  final parsed = int.tryParse(values.last);
  if (parsed == null || parsed < Ajuste.minimo || parsed > Ajuste.maximo) {
    throw const ErrorDeSolicitud('"ajuste" debe ser un entero entre 50 y 150.');
  }
  return parsed;
}

Map<String, int> _exerciseAdjustments(List<String>? values) {
  final result = <String, int>{};
  for (final value in values ?? const <String>[]) {
    final colon = value.lastIndexOf(':');
    final id = colon <= 0 ? '' : value.substring(0, colon);
    final parsed = colon <= 0 ? null : int.tryParse(value.substring(colon + 1));
    if (id.isEmpty ||
        parsed == null ||
        parsed < Ajuste.minimo ||
        parsed > Ajuste.maximo) {
      throw const ErrorDeSolicitud(
        '"ajusteEjercicio" debe ser <ejercicioId>:<entero entre 50 y 150>.',
      );
    }
    result[id] = parsed;
  }
  return result;
}
