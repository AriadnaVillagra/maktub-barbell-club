import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "create assignment" slice reads and writes.
abstract interface class CreateAssignmentStore {
  /// Whether the plan [planId] of [clubId] has a published version: null if the club has no such plan.
  Future<bool?> planIsPublished(String clubId, String planId);

  /// Whether the group [groupId] exists in [clubId].
  Future<bool> groupExists(String clubId, String groupId);

  /// Whether the athlete [athleteId] exists in [clubId].
  Future<bool> athleteExists(String clubId, String athleteId);

  /// Inserts [assignment]. Returns false, and writes nothing, if its owner (group or athlete) already has an
  /// active assignment: the store enforces "at most one active per owner" atomically, not the caller.
  Future<bool> insert(Assignment assignment);
}

class MongoCreateAssignmentStore implements CreateAssignmentStore {
  MongoCreateAssignmentStore(this._db);

  final Db _db;

  @override
  Future<bool?> planIsPublished(String clubId, String planId) async {
    final doc = await _db.collection(Colecciones.planes).findOne({
      '_id': planId,
      'clubId': clubId,
    });
    return doc == null ? null : doc['publicado'] != null;
  }

  @override
  Future<bool> groupExists(String clubId, String groupId) async =>
      await _db.collection(Colecciones.grupos).findOne({
        '_id': groupId,
        'clubId': clubId,
      }) !=
      null;

  @override
  Future<bool> athleteExists(String clubId, String athleteId) async =>
      await _db.collection(Colecciones.atletas).findOne({
        '_id': athleteId,
        'clubId': clubId,
      }) !=
      null;

  // Two concurrent requests for the same owner cannot both pass: the unique partial indexes
  // `club_grupo_activa_unica` and `club_atleta_activa_unica` (see `asegurarIndices`) reject the second insert
  // with a duplicate key error.
  @override
  Future<bool> insert(Assignment assignment) async {
    final result = await _db
        .collection(Colecciones.asignaciones)
        .insertOne(aDocumento(assignment.toJson()));
    if (result.isSuccess) return true;
    if (result.writeError?.code == _duplicateKey) return false;
    throw StateError('Could not insert the assignment: ${result.writeError}');
  }
}

const _duplicateKey = 11000;
