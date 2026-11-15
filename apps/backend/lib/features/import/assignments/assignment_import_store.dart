import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the assignments import reads. It never writes: assignments go through E6's create-assignment use case.
abstract interface class AssignmentImportStore {
  /// The groups of [clubId].
  Future<List<AthleteGroup>> groups(String clubId);

  /// The athletes of [clubId].
  Future<List<Atleta>> athletes(String clubId);

  /// The plans of [clubId] among [ids] that have a published version.
  Future<Set<String>> publishedPlanIds(String clubId, Set<String> ids);

  /// The plans of [clubId] among [ids], published or not.
  Future<Set<String>> planIds(String clubId, Set<String> ids);

  /// The assignments of [clubId] among [ids], by id.
  Future<Map<String, Assignment>> assignments(String clubId, Set<String> ids);
}

class MongoAssignmentImportStore implements AssignmentImportStore {
  MongoAssignmentImportStore(this._db);

  final Db _db;

  Future<List<Json>> _find(String collection, Map<String, Object> filter) async => [
    for (final d in await _db.collection(collection).find(filter).toList()) desdeDocumento(d),
  ];

  @override
  Future<List<AthleteGroup>> groups(String clubId) async => [
    for (final j in await _find(Colecciones.grupos, {'clubId': clubId})) AthleteGroup.fromJson(j),
  ];

  @override
  Future<List<Atleta>> athletes(String clubId) async => [
    for (final j in await _find(Colecciones.atletas, {'clubId': clubId})) Atleta.fromJson(j),
  ];

  @override
  Future<Set<String>> publishedPlanIds(String clubId, Set<String> ids) async => {
    for (final j in await _find(Colecciones.planes, {
      'clubId': clubId,
      '_id': {r'$in': ids.toList()},
      'publicado': {r'$ne': null},
    }))
      '${j['id']}',
  };

  @override
  Future<Set<String>> planIds(String clubId, Set<String> ids) async => {
    for (final j in await _find(Colecciones.planes, {
      'clubId': clubId,
      '_id': {r'$in': ids.toList()},
    }))
      '${j['id']}',
  };

  @override
  Future<Map<String, Assignment>> assignments(String clubId, Set<String> ids) async => {
    for (final j in await _find(Colecciones.asignaciones, {
      'clubId': clubId,
      '_id': {r'$in': ids.toList()},
    }))
      for (final a in [Assignment.fromJson(j)]) a.id: a,
  };
}
