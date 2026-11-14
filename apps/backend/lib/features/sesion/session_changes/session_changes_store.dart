import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "changes since a number" slice reads. Every method carries the club id.
abstract interface class SessionChangesStore {
  /// The session [sessionId] of [clubId], or null if the club has none with that id.
  Future<Session?> session(String clubId, String sessionId);

  /// The records of the session whose last change has a number above [since].
  Future<List<SetRecord>> recordsAfter(
    String clubId,
    String sessionId,
    int since,
  );

  /// The athlete of [clubId] linked to the user [userId], or null if the user is not an athlete there.
  Future<String?> athleteIdOfUser(String clubId, String userId);

  /// The group of the assignment [assignmentId] of [clubId], or null if the club has none with that id.
  Future<String?> groupIdOfAssignment(String clubId, String assignmentId);

  /// The athlete ids of the group [groupId] of [clubId]; empty if the group is not in the club.
  Future<List<String>> groupMemberIds(String clubId, String groupId);
}

class MongoSessionChangesStore implements SessionChangesStore {
  MongoSessionChangesStore(this._db);

  final Db _db;

  @override
  Future<Session?> session(String clubId, String sessionId) async {
    final doc = await _db.collection(Colecciones.sesiones).findOne({
      '_id': sessionId,
      'clubId': clubId,
    });
    return doc == null ? null : Session.fromJson(desdeDocumento(doc));
  }

  @override
  Future<List<SetRecord>> recordsAfter(
    String clubId,
    String sessionId,
    int since,
  ) async {
    final docs = await _db.collection(Colecciones.registros).find({
      'clubId': clubId,
      'sesionId': sessionId,
      'secuencia': {r'$gt': since},
    }).toList();
    return [for (final d in docs) SetRecord.fromJson(desdeDocumento(d))];
  }

  @override
  Future<String?> athleteIdOfUser(String clubId, String userId) async {
    final doc = await _db.collection(Colecciones.atletas).findOne({
      'clubId': clubId,
      'usuarioId': userId,
    });
    return doc == null ? null : '${doc['_id']}';
  }

  @override
  Future<String?> groupIdOfAssignment(
    String clubId,
    String assignmentId,
  ) async {
    final doc = await _db.collection(Colecciones.asignaciones).findOne({
      '_id': assignmentId,
      'clubId': clubId,
    });
    return doc == null
        ? null
        : Assignment.fromJson(desdeDocumento(doc)).groupId;
  }

  @override
  Future<List<String>> groupMemberIds(String clubId, String groupId) async {
    final doc = await _db.collection(Colecciones.grupos).findOne({
      '_id': groupId,
      'clubId': clubId,
    });
    return doc == null
        ? const []
        : AthleteGroup.fromJson(desdeDocumento(doc)).memberIds;
  }
}
