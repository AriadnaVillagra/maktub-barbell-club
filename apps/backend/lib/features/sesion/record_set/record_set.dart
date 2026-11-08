import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/sesion/record_view.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'record_set_store.dart';

/// `PUT /clubes/{clubId}/sesiones/{sesionId}/registros` body `{atletaId, bloque, prescripcion, serie, hecha?, kilos?,
/// kilosManual?, ajuste?, reps?, segundos?, distanciaM?, calorias?, rpe?}` → 200 with the stored `SetRecord`.
/// Needs [Accion.registrar]. Writes that one set and nothing else, so repeating it changes nothing and two
/// devices writing different sets do not touch each other (diseno, "Multi-dispositivo").
///
/// The position is 0-based and must exist in the plan's published version. The server takes the exercise, its name
/// and the target from there, and resolves RM, work factor, fixed weight and bar itself on the session's date:
/// - Without `kilosManual`, the kilos are computed; `kilos` is ignored. `ajuste` is the day's adjustment already
///   resolved for this exercise (50..150, default 100).
/// - With `kilosManual: true`, `kilos` is mandatory and both percents follow from it (E4.5).
/// - `reps`, `segundos`, `distanciaM` and `calorias` default to the target's when omitted.
///
/// A coach writes for any present athlete, and an athlete present in the session for any present athlete
/// (in a personal club, only for themselves). 400 if the body is malformed, 403 if the user cannot write for that
/// athlete, 404 if the session is not in the club, 422 if the athlete is not present, the position is not in the
/// plan or the plan has no published version. [store], [newId] and [now] are for tests.
Future<Response> recordSetEndpoint(
  RequestContext context,
  String sessionId, {
  RecordSetStore? store,
  String Function()? newId,
  DateTime Function()? now,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.registrar);
  final body = await leerCuerpoJson(context.request);
  final record = await RecordSet(
    store ?? MongoRecordSetStore(context.read<Db>()),
    newId: newId,
    now: now,
  )(club, sessionId, body);
  return Response.json(body: recordForViewer(record, club));
}

class RecordSet {
  RecordSet(
    this._store, {
    String Function()? newId,
    DateTime Function()? now,
  }) : _newId = newId ?? (() => ObjectId().oid),
       _now = now ?? DateTime.now;

  final RecordSetStore _store;
  final String Function() _newId;
  final DateTime Function() _now;

  Future<SetRecord> call(
    ClubContext club,
    String sessionId,
    Json body,
  ) async {
    final input = _SetInput.fromBody(body);
    final session = await _store.session(club.clubId, sessionId);
    if (session == null) {
      throw const ErrorDeSolicitud.noEncontrado('Sesión no encontrada.');
    }
    await _authorize(club, session, input.athleteId);

    final published = await _store.publishedPlan(club.clubId, session.planId);
    if (published == null) {
      throw _unprocessable('El plan de la sesión no tiene una versión publicada.');
    }
    final prescription = _prescriptionAt(published, session, input);
    final target = prescription.sets[input.setIndex];
    final exercises = await _store.exercises(club.clubId);
    final exercise = exercises[prescription.exerciseId];
    if (exercise == null) {
      throw _unprocessable('El ejercicio de esa serie no existe en el catálogo.');
    }

    final load = await _resolveLoad(
      club,
      session,
      input,
      target,
      prescription,
      exercise,
      exercises,
    );
    final now = _now();
    return _store.upsert(
      SetRecord(
        id: _newId(),
        clubId: club.clubId,
        sessionId: session.id,
        athleteId: input.athleteId,
        exerciseId: exercise.id,
        exerciseName: exercise.name,
        blockIndex: input.blockIndex,
        prescriptionIndex: input.prescriptionIndex,
        setIndex: input.setIndex,
        target: target,
        done: input.done,
        kg: load.kg,
        reps: input.reps ?? target.reps,
        seconds: input.seconds ?? target.seconds,
        distanceM: input.distanceM ?? target.distanceM,
        calories: input.calories ?? target.calories,
        referenceId: load.reference?.id,
        referenceValue: load.reference?.value,
        workFactor: load.workFactor,
        pctPlan: load.pcts?.pctPlan,
        pctReal: load.pcts?.pctReal,
        rpe: input.rpe,
        manualKg: input.manualKg,
        writtenBy: club.userId,
        auditoria: Auditoria.nueva(
          club.userId,
          ahora: now,
        ).modificada(club.userId, ahora: now),
      ),
    );
  }

  Future<void> _authorize(
    ClubContext club,
    Session session,
    String athleteId,
  ) async {
    final present = session.presentAthleteIds;
    if (!present.contains(athleteId)) {
      throw _unprocessable('Ese atleta no está presente en la sesión.');
    }
    if (club.can(Accion.planificar)) return;
    final own = await _store.athleteIdOfUser(club.clubId, club.userId);
    final allowed =
        own != null &&
        present.contains(own) &&
        (club.clubType != TipoClub.personal || own == athleteId);
    if (!allowed) throw forbiddenRole;
  }

  Prescription _prescriptionAt(
    PublishedPlan plan,
    Session session,
    _SetInput input,
  ) {
    final days = plan.weekModelOf(session.week)?.days ?? const <PlanDay>[];
    final blocks = session.day <= days.length
        ? days[session.day - 1].blocks
        : const <PlanBlock>[];
    final prescriptions = input.blockIndex < blocks.length
        ? blocks[input.blockIndex].prescriptions
        : const <Prescription>[];
    if (input.prescriptionIndex >= prescriptions.length ||
        input.setIndex >= prescriptions[input.prescriptionIndex].sets.length) {
      throw _unprocessable('Esa serie no existe en el plan publicado.');
    }
    return prescriptions[input.prescriptionIndex];
  }

  Future<_Load> _resolveLoad(
    ClubContext club,
    Session session,
    _SetInput input,
    PlanSet target,
    Prescription prescription,
    Exercise exercise,
    Map<String, Exercise> exercises,
  ) async {
    final clubId = club.clubId;
    final rmExerciseId = exercise.loadReference.kind == LoadReferenceKind.none
        ? null
        : effectiveRmExerciseId(exercise.id, exercises);
    final references = rmExerciseId == null
        ? const <Reference>[]
        : await _store.references(clubId, input.athleteId, rmExerciseId);
    final factors = rmExerciseId == null
        ? const <WorkFactor>[]
        : await _store.workFactors(clubId, input.athleteId, rmExerciseId);
    final reference = rmExerciseId == null
        ? null
        : currentReference(
            references,
            athleteId: input.athleteId,
            exerciseId: rmExerciseId,
            type: ReferenceType.rm,
            on: session.date,
          );
    final factor = rmExerciseId == null
        ? defaultWorkFactor
        : currentWorkFactor(
            factors,
            references,
            athleteId: input.athleteId,
            exerciseId: rmExerciseId,
            on: session.date,
          );
    final pct = target.pct;
    final byRm = rmExerciseId != null && pct != null && pct > 0;

    if (input.manualKg) {
      final pcts = byRm
          ? RecordPcts.fromWeight(input.kg!, reference?.value, workFactor: factor)
          : null;
      return _Load.of(input.kg, pcts, reference, factor);
    }

    final applied = pct == null ? null : pctEfectivo(pct, input.adjustment);
    final fixed = byRm
        ? null
        : await _store.fixedWeight(clubId, input.athleteId, exercise.id);
    final proposal = proposeLoad(
      hasReference: rmExerciseId != null,
      pct: applied,
      rm: reference?.value,
      fixedKg: fixed?.kg ?? target.kg,
      equipo: await _store.equipment(clubId) ?? Equipo.estandarDe(clubId),
      workFactor: factor,
      barKg: prescription.barKg ?? exercise.barKg,
    );
    final kg = proposal.weightKg;
    final pcts = byRm && kg != null
        ? RecordPcts.fromPlan(applied!, workFactor: factor)
        : null;
    return _Load.of(kg, pcts, reference, factor);
  }
}

ErrorDeSolicitud _unprocessable(String message) =>
    ErrorDeSolicitud(message, estado: HttpStatus.unprocessableEntity);

/// The weight of a record and what it came from. The RM and factor are kept only when percents were derived.
class _Load {
  const _Load(this.kg, this.pcts, this.reference, this.workFactor);

  factory _Load.of(
    double? kg,
    RecordPcts? pcts,
    Reference? reference,
    double factor,
  ) => pcts == null
      ? _Load(kg, null, null, null)
      : _Load(
          kg,
          pcts,
          reference,
          factor == defaultWorkFactor ? null : factor,
        );

  final double? kg;
  final RecordPcts? pcts;
  final Reference? reference;
  final double? workFactor;
}

class _SetInput {
  _SetInput({
    required this.athleteId,
    required this.blockIndex,
    required this.prescriptionIndex,
    required this.setIndex,
    required this.done,
    required this.manualKg,
    required this.adjustment,
    this.kg,
    this.reps,
    this.seconds,
    this.distanceM,
    this.calories,
    this.rpe,
  });

  factory _SetInput.fromBody(Json body) {
    final athleteId = body['atletaId'] is String
        ? (body['atletaId'] as String).trim()
        : '';
    if (athleteId.isEmpty) {
      throw const ErrorDeSolicitud('"atletaId" es obligatorio.');
    }
    final manualKg = body['kilosManual'] == true;
    final kg = _nonNegative(body['kilos'], 'kilos');
    if (manualKg && kg == null) {
      throw const ErrorDeSolicitud(
        '"kilos" es obligatorio cuando los kilos son manuales.',
      );
    }
    final rpe = _nonNegative(body['rpe'], 'rpe');
    if (rpe != null && (rpe < 6 || rpe > 10 || rpe * 2 != (rpe * 2).round())) {
      throw const ErrorDeSolicitud(
        '"rpe" debe estar entre 6 y 10, de a medios puntos.',
      );
    }
    return _SetInput(
      athleteId: athleteId,
      blockIndex: _index(body['bloque'], 'bloque'),
      prescriptionIndex: _index(body['prescripcion'], 'prescripcion'),
      setIndex: _index(body['serie'], 'serie'),
      done: body['hecha'] != false,
      manualKg: manualKg,
      adjustment: snapAdjustment(
        _nonNegative(body['ajuste'], 'ajuste')?.round() ?? Ajuste.neutro,
      ),
      kg: kg,
      reps: _nonNegative(body['reps'], 'reps')?.round(),
      seconds: _nonNegative(body['segundos'], 'segundos')?.round(),
      distanceM: _nonNegative(body['distanciaM'], 'distanciaM'),
      calories: _nonNegative(body['calorias'], 'calorias'),
      rpe: rpe,
    );
  }

  final String athleteId;
  final int blockIndex;
  final int prescriptionIndex;
  final int setIndex;
  final bool done;
  final bool manualKg;

  /// The day's adjustment in force for this exercise, resolved by the client (see `effectiveAdjustment`).
  final int adjustment;
  final double? kg;
  final int? reps;
  final int? seconds;
  final double? distanceM;
  final double? calories;
  final double? rpe;
}

int _index(Object? value, String field) {
  final index = value is num && value == value.roundToDouble()
      ? value.toInt()
      : null;
  if (index == null || index < 0) {
    throw ErrorDeSolicitud('"$field" debe ser un entero desde 0.');
  }
  return index;
}

double? _nonNegative(Object? value, String field) {
  if (value == null) return null;
  if (value is! num || value < 0) {
    throw ErrorDeSolicitud('"$field" debe ser un número no negativo.');
  }
  return value.toDouble();
}
