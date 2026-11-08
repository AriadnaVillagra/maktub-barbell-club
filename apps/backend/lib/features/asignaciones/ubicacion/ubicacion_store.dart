import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "location by date" slice reads.
abstract interface class LocationStore {
  /// Whether the group [groupId] exists in [clubId].
  Future<bool> groupExists(String clubId, String groupId);

  /// The active assignment of [groupId] in [clubId], or null if it has none.
  Future<Assignment?> activeAssignment(String clubId, String groupId);

  /// Whether the plan [planId] of [clubId] has a published version.
  Future<bool> planIsPublished(String clubId, String planId);
}

class MongoLocationStore implements LocationStore {
  MongoLocationStore(this._db);

  final Db _db;

  @override
  Future<bool> groupExists(String clubId, String groupId) async =>
      await _db.collection(Colecciones.grupos).findOne({
        '_id': groupId,
        'clubId': clubId,
      }) !=
      null;

  @override
  Future<Assignment?> activeAssignment(String clubId, String groupId) async {
    final doc = await _db.collection(Colecciones.asignaciones).findOne({
      'clubId': clubId,
      'grupoId': groupId,
      'estado': AssignmentStatus.active.cable,
    });
    return doc == null ? null : Assignment.fromJson(desdeDocumento(doc));
  }

  @override
  Future<bool> planIsPublished(String clubId, String planId) async {
    final doc = await _db.collection(Colecciones.planes).findOne({
      '_id': planId,
      'clubId': clubId,
    });
    return doc != null && doc['publicado'] != null;
  }
}
