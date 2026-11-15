import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the history import reads. It never writes: sessions, sets and block times go through the E7 use cases
/// (open a session, record a set, record a block time).
abstract interface class HistoryImportStore {
  /// The plans of [clubId] among [ids], by id (with their published version).
  Future<Map<String, Plan>> plans(String clubId, Set<String> ids);

  /// The assignments of [clubId] of any of [planIds], whatever their status.
  Future<List<Assignment>> assignments(String clubId, Set<String> planIds);

  /// The groups of [clubId] among [ids]: group id → athlete ids.
  Future<Map<String, List<String>>> groupMembers(String clubId, Set<String> ids);

  /// The sessions of [clubId] of any of [assignmentIds].
  Future<List<Session>> sessions(String clubId, Set<String> assignmentIds);

  /// The set records of [clubId] in any of [sessionIds].
  Future<List<SetRecord>> records(String clubId, Set<String> sessionIds);

  /// The block times of [clubId] in any of [sessionIds].
  Future<List<BlockTime>> blockTimes(String clubId, Set<String> sessionIds);

  /// The fixed weights of [clubId].
  Future<List<FixedWeight>> fixedWeights(String clubId);
}

class MongoHistoryImportStore implements HistoryImportStore {
  MongoHistoryImportStore(this._db);

  final Db _db;

  Future<List<Json>> _find(String collection, Map<String, Object> filter) async => [
    for (final d in await _db.collection(collection).find(filter).toList()) desdeDocumento(d),
  ];

  @override
  Future<Map<String, Plan>> plans(String clubId, Set<String> ids) async => {
    for (final j in await _find(Colecciones.planes, {
      'clubId': clubId,
      '_id': {r'$in': ids.toList()},
    }))
      for (final p in [Plan.fromJson(j)]) p.id: p,
  };

  @override
  Future<List<Assignment>> assignments(String clubId, Set<String> planIds) async => [
    for (final j in await _find(Colecciones.asignaciones, {
      'clubId': clubId,
      'planId': {r'$in': planIds.toList()},
    }))
      Assignment.fromJson(j),
  ];

  @override
  Future<Map<String, List<String>>> groupMembers(String clubId, Set<String> ids) async => {
    for (final j in await _find(Colecciones.grupos, {
      'clubId': clubId,
      '_id': {r'$in': ids.toList()},
    }))
      for (final g in [AthleteGroup.fromJson(j)]) g.id: g.memberIds,
  };

  @override
  Future<List<Session>> sessions(String clubId, Set<String> assignmentIds) async => [
    for (final j in await _find(Colecciones.sesiones, {
      'clubId': clubId,
      'asignacionId': {r'$in': assignmentIds.toList()},
    }))
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

  @override
  Future<List<BlockTime>> blockTimes(String clubId, Set<String> sessionIds) async => [
    for (final j in await _find(Colecciones.tiemposBloque, {
      'clubId': clubId,
      'sesionId': {r'$in': sessionIds.toList()},
    }))
      BlockTime.fromJson(j),
  ];

  @override
  Future<List<FixedWeight>> fixedWeights(String clubId) async => [
    for (final j in await _find(Colecciones.kilajesFijos, {'clubId': clubId})) FixedWeight.fromJson(j),
  ];
}
