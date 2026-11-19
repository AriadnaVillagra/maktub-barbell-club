import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "create assignment" slice reads and writes.
abstract interface class CreateAssignmentStore {
  /// The plan [planId] of [clubId]; null if the club has no such plan.
  Future<Plan?> plan(String clubId, String planId);

  /// The members of the group [groupId] of [clubId]; null if the club has no such group.
  Future<List<String>?> groupMemberIds(String clubId, String groupId);

  /// Whether every one of [athleteIds] is an athlete of [clubId].
  Future<bool> athletesExist(String clubId, Set<String> athleteIds);

  /// Inserts [assignment].
  Future<void> insert(Assignment assignment);
}

class MongoCreateAssignmentStore implements CreateAssignmentStore {
  MongoCreateAssignmentStore(this._db);

  final Db _db;

  @override
  Future<Plan?> plan(String clubId, String planId) async {
    final doc = await _db.collection(Colecciones.planes).findOne({
      '_id': planId,
      'clubId': clubId,
    });
    return doc == null ? null : Plan.fromJson(desdeDocumento(doc));
  }

  @override
  Future<List<String>?> groupMemberIds(String clubId, String groupId) async {
    final doc = await _db.collection(Colecciones.grupos).findOne({
      '_id': groupId,
      'clubId': clubId,
    });
    if (doc == null) return null;
    return [for (final m in (doc['miembros'] as List? ?? const [])) '$m'];
  }

  @override
  Future<bool> athletesExist(String clubId, Set<String> athleteIds) async {
    final found = await _db.collection(Colecciones.atletas).find({
      'clubId': clubId,
      '_id': {r'$in': athleteIds.toList()},
    }).toList();
    return found.length == athleteIds.length;
  }

  @override
  Future<void> insert(Assignment assignment) async {
    final result = await _db
        .collection(Colecciones.asignaciones)
        .insertOne(aDocumento(assignment.toJson()));
    if (!result.isSuccess) {
      throw StateError('Could not insert the assignment: ${result.writeError}');
    }
  }
}
