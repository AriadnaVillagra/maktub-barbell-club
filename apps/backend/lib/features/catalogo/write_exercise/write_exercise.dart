import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'write_exercise_store.dart';

/// Writes of exercises (F2). Creating needs [Accion.editarCatalogoClub]; changing an existing one is
/// authorized once it is loaded, because a default one needs a platform admin instead.
///
/// `POST   .../catalogo/ejercicios` body: the exercise without `id`, `clubId`, `estado`, `auditoria` → the
///   created exercise (200, active)
/// `PUT    .../catalogo/ejercicios/<id>` same body → the exercise (replaces its editable fields)
/// `PATCH  .../catalogo/ejercicios/<id>` `{estado: activo|archivado}` → the exercise
/// `DELETE .../catalogo/ejercicios/<id>` → `{resultado: borrado|archivado, id, ejercicio?}`: deleted when
///   nothing uses it, archived otherwise.
///
/// A change to a default exercise (`clubId` = `plataforma`) reaches every club. The server sets `id`, `clubId`,
/// `estado` and `auditoria`. [store], [usage], [newId] and [now] are for tests.
Future<Response> createExerciseEndpoint(
  RequestContext context, {
  WriteExerciseStore? store,
  ExerciseUsage? usage,
  String Function()? newId,
  DateTime Function()? now,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.editarCatalogoClub);
  final created = await _useCase(context, store, usage, newId, now).create(club, await leerCuerpoJson(context.request));
  return Response.json(body: created.toJson());
}

Future<Response> updateExerciseEndpoint(
  RequestContext context,
  String id, {
  WriteExerciseStore? store,
  ExerciseUsage? usage,
  String Function()? newId,
  DateTime Function()? now,
}) async {
  final club = context.read<ClubContext>();
  final updated = await _useCase(
    context,
    store,
    usage,
    newId,
    now,
  ).update(club, id, await leerCuerpoJson(context.request));
  return Response.json(body: updated.toJson());
}

Future<Response> setExerciseStatusEndpoint(
  RequestContext context,
  String id, {
  WriteExerciseStore? store,
  ExerciseUsage? usage,
  String Function()? newId,
  DateTime Function()? now,
}) async {
  final club = context.read<ClubContext>();
  final updated = await _useCase(
    context,
    store,
    usage,
    newId,
    now,
  ).setStatus(club, id, await leerCuerpoJson(context.request));
  return Response.json(body: updated.toJson());
}

Future<Response> deleteExerciseEndpoint(
  RequestContext context,
  String id, {
  WriteExerciseStore? store,
  ExerciseUsage? usage,
  String Function()? newId,
  DateTime Function()? now,
}) async {
  final club = context.read<ClubContext>();
  final result = await _useCase(context, store, usage, newId, now).remove(club, id);
  return Response.json(
    body: {
      'resultado': result.deleted ? 'borrado' : 'archivado',
      'id': id,
      if (result.archived != null) 'ejercicio': result.archived!.toJson(),
    },
  );
}

WriteExercise _useCase(
  RequestContext context,
  WriteExerciseStore? store,
  ExerciseUsage? usage,
  String Function()? newId,
  DateTime Function()? now,
) => WriteExercise(
  store ?? MongoWriteExerciseStore(context.read<Db>()),
  usage ?? MongoExerciseUsage(context.read<Db>()),
  newId: newId,
  now: now,
);

/// What [WriteExercise.remove] did.
class RemoveExerciseResult {
  const RemoveExerciseResult.deleted() : deleted = true, archived = null;
  const RemoveExerciseResult.archived(Exercise this.archived) : deleted = false;

  final bool deleted;
  final Exercise? archived;
}

class WriteExercise {
  WriteExercise(this._store, this._usage, {String Function()? newId, DateTime Function()? now})
    : _newId = newId ?? (() => ObjectId().oid),
      _now = now ?? DateTime.now;

  final WriteExerciseStore _store;
  final ExerciseUsage _usage;
  final String Function() _newId;
  final DateTime Function() _now;

  Future<Exercise> create(ClubContext club, Json body) async {
    final view = await _store.view({clubPlataforma, club.clubId});
    final exercise = _parse(
      body,
      id: _newId(),
      clubId: club.clubId,
      audit: Auditoria.nueva(club.userId, ahora: _now()),
    );
    _validate(exercise, view);
    await _store.insert(exercise);
    return exercise;
  }

  Future<Exercise> update(ClubContext club, String id, Json body) async {
    final view = await _store.view({clubPlataforma, club.clubId});
    final current = _writable(club, view, id);
    final exercise = _parse(
      body,
      id: id,
      clubId: current.clubId,
      audit: current.auditoria.modificada(club.userId, ahora: _now()),
      status: current.status,
    );
    _validate(exercise, view);
    await _store.replace(exercise);
    return exercise;
  }

  Future<Exercise> setStatus(ClubContext club, String id, Json body) async {
    final CatalogStatus status;
    try {
      status = CatalogStatus.deCable(body['estado']);
    } on Object {
      throw const ErrorDeSolicitud('El estado debe ser "activo" o "archivado".');
    }
    final current = _writable(club, await _store.view({clubPlataforma, club.clubId}), id);
    final updated = current.copyWith(
      status: status,
      auditoria: current.auditoria.modificada(club.userId, ahora: _now()),
    );
    await _store.replace(updated);
    return updated;
  }

  /// Deletes the exercise if nothing uses it; otherwise archives it (it keeps resolving where it is used).
  Future<RemoveExerciseResult> remove(ClubContext club, String id) async {
    final current = _writable(club, await _store.view({clubPlataforma, club.clubId}), id);
    if (!await _usage.isUsed(current.clubId, id)) {
      await _store.delete(current.clubId, id);
      return const RemoveExerciseResult.deleted();
    }
    final archived = current.copyWith(
      status: CatalogStatus.archived,
      auditoria: current.auditoria.modificada(club.userId, ahora: _now()),
    );
    await _store.replace(archived);
    return RemoveExerciseResult.archived(archived);
  }

  /// Builds the exercise from the body; the server's fields win over anything the client sent.
  Exercise _parse(
    Json body, {
    required String id,
    required String clubId,
    required Auditoria audit,
    CatalogStatus status = CatalogStatus.active,
  }) {
    final raw = body['nombre'];
    final name = raw is String ? raw.trim().replaceAll(RegExp(r'\s+'), ' ') : '';
    if (name.isEmpty) throw const ErrorDeSolicitud('El nombre es obligatorio.');
    try {
      return Exercise.fromJson({
        ...body,
        'id': id,
        'clubId': clubId,
        'nombre': name,
        'estado': status.cable,
        'auditoria': audit.toJson(),
      });
    } on FormatException {
      rethrow;
    } on Object {
      throw const ErrorDeSolicitud('El ejercicio no tiene el formato esperado.');
    }
  }

  void _validate(Exercise exercise, CatalogView view) {
    if (exercise.suggestionIds.contains(exercise.id)) {
      throw const ErrorDeSolicitud('Un ejercicio no puede sugerirse a sí mismo.');
    }
    final problems = validateExercise(exercise, view);
    if (problems.isNotEmpty) throw ErrorDeSolicitud(problems.map(_message).join(' '));
    if (isExerciseNameTaken(exercise.name, view.exercises.values, exceptId: exercise.id)) {
      throw const ErrorDeSolicitud('Ya hay un ejercicio con ese nombre.', estado: HttpStatus.conflict);
    }
  }

  /// The exercise [id] if the user can change it; 404 if not visible, 403 without permission.
  Exercise _writable(ClubContext club, CatalogView view, String id) {
    final found = view.exercises[id];
    if (found == null || !isVisibleTo(found, club.clubId)) {
      throw const ErrorDeSolicitud.noEncontrado('Ejercicio no encontrado.');
    }
    club.authorizeCatalogWrite(found);
    return found;
  }

  String _message(CatalogProblem p) => switch (p) {
    CatalogProblem.ownReferenceNeedsLoadAndReps =>
      'La referencia "propia" necesita que el ejercicio mida carga y repeticiones.',
    CatalogProblem.defaultMetricNotInMetrics => 'La métrica objetivo debe estar entre las métricas del ejercicio.',
    CatalogProblem.referenceTargetNotVisible => 'El ejercicio de referencia no existe.',
    CatalogProblem.referenceCycle => 'Las referencias de carga forman un ciclo.',
    CatalogProblem.baseReferencesClub => 'Un ejercicio default no puede referenciar a uno del club.',
    CatalogProblem.itemNotVisible => 'Una categoría, patrón, músculo o sugerencia no existe.',
    CatalogProblem.baseUsesClubItem => 'Un ejercicio default no puede usar elementos del club.',
    CatalogProblem.notesTooLong => 'Las notas superan los $maxExerciseNotes caracteres.',
    CatalogProblem.barNotPositive => 'La barra debe pesar más de 0.',
    CatalogProblem.baseNodeWithParent ||
    CatalogProblem.parentNotVisible ||
    CatalogProblem.depthExceeded => 'Jerarquía inválida.',
  };
}
