import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the grid step reads. It never writes: the plan, the assignment, the sessions and the sets go through their
/// use cases.
abstract interface class GridImportStore {
  /// The plan [id] of [clubId], with its published version, or null.
  Future<Plan?> plan(String clubId, String id);

  /// The assignment [id] of [clubId], or null.
  Future<Assignment?> assignment(String clubId, String id);

  /// The groups of [clubId].
  Future<List<AthleteGroup>> groups(String clubId);

  /// The athletes of [clubId] among [ids], by id.
  Future<Map<String, Atleta>> athletes(String clubId, Set<String> ids);

  /// The exercises visible to [clubId] (default plus its own, archived included), by id.
  Future<Map<String, Exercise>> exercises(String clubId);

  /// The sessions of [clubId] of the assignment [assignmentId].
  Future<List<Session>> sessions(String clubId, String assignmentId);

  /// The set records of [clubId] in any of [sessionIds].
  Future<List<SetRecord>> records(String clubId, Set<String> sessionIds);

  /// Every reference of [athleteIds] in [clubId].
  Future<List<Reference>> references(String clubId, Set<String> athleteIds);

  /// Every work factor of [athleteIds] in [clubId].
  Future<List<WorkFactor>> workFactors(String clubId, Set<String> athleteIds);

  /// The fixed weights of [athleteIds] in [clubId].
  Future<List<FixedWeight>> fixedWeights(String clubId, Set<String> athleteIds);

  /// The club's equipment, or null if it never saved one.
  Future<Equipo?> equipment(String clubId);
}

class MongoGridImportStore implements GridImportStore {
  MongoGridImportStore(this._db);

  final Db _db;

  Future<List<Json>> _find(String collection, Map<String, Object> filter) async => [
    for (final d in await _db.collection(collection).find(filter).toList()) desdeDocumento(d),
  ];

  @override
  Future<Plan?> plan(String clubId, String id) async {
    final found = await _find(Colecciones.planes, {'clubId': clubId, '_id': id});
    return found.isEmpty ? null : Plan.fromJson(found.single);
  }

  @override
  Future<Assignment?> assignment(String clubId, String id) async {
    final found = await _find(Colecciones.asignaciones, {'clubId': clubId, '_id': id});
    return found.isEmpty ? null : Assignment.fromJson(found.single);
  }

  @override
  Future<List<AthleteGroup>> groups(String clubId) async => [
    for (final j in await _find(Colecciones.grupos, {'clubId': clubId})) AthleteGroup.fromJson(j),
  ];

  @override
  Future<Map<String, Atleta>> athletes(String clubId, Set<String> ids) async => {
    for (final j in await _find(Colecciones.atletas, {
      'clubId': clubId,
      '_id': {r'$in': ids.toList()},
    }))
      for (final a in [Atleta.fromJson(j)]) a.id: a,
  };

  @override
  Future<Map<String, Exercise>> exercises(String clubId) async => {
    for (final j in await _find(Colecciones.ejercicios, {
      'clubId': {
        r'$in': [clubId, clubPlataforma],
      },
    }))
      for (final e in [Exercise.fromJson(j)]) e.id: e,
  };

  @override
  Future<List<Session>> sessions(String clubId, String assignmentId) async => [
    for (final j in await _find(Colecciones.sesiones, {'clubId': clubId, 'asignacionId': assignmentId}))
      Session.fromJson(j),
  ];

  @override
  Future<List<SetRecord>> records(String clubId, Set<String> sessionIds) async => [
    for (final j in await _find(Colecciones.registros, {
      'clubId': clubId,
      'sesionId': {r'$in': sessionIds.toList()},
    }))
      SetRecord.fromJson(j),
  ];

  Map<String, Object> _ofAthletes(String clubId, Set<String> athleteIds) => {
    'clubId': clubId,
    'atletaId': {r'$in': athleteIds.toList()},
  };

  @override
  Future<List<Reference>> references(String clubId, Set<String> athleteIds) async => [
    for (final j in await _find(Colecciones.referencias, _ofAthletes(clubId, athleteIds))) Reference.fromJson(j),
  ];

  @override
  Future<List<WorkFactor>> workFactors(String clubId, Set<String> athleteIds) async => [
    for (final j in await _find(Colecciones.factoresTrabajo, _ofAthletes(clubId, athleteIds))) WorkFactor.fromJson(j),
  ];

  @override
  Future<List<FixedWeight>> fixedWeights(String clubId, Set<String> athleteIds) async => [
    for (final j in await _find(Colecciones.kilajesFijos, _ofAthletes(clubId, athleteIds))) FixedWeight.fromJson(j),
  ];

  @override
  Future<Equipo?> equipment(String clubId) async {
    final found = await _find(Colecciones.equipos, {'clubId': clubId, '_id': clubId});
    return found.isEmpty ? null : Equipo.fromJson(found.single);
  }
}
