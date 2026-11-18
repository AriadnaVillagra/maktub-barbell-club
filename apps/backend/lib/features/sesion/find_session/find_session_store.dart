import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "find the session of a day" slice reads. It never writes. Every method carries the club id.
abstract interface class FindSessionStore {
  /// The assignment [assignmentId] of [clubId], or null if the club has none with that id.
  Future<Assignment?> assignment(String clubId, String assignmentId);

  /// The athlete of [clubId] linked to the user [userId], or null if the user is not an athlete there.
  Future<String?> athleteIdOfUser(String clubId, String userId);

  /// The session stored with that key (club, assignment, date, week and day), or null.
  Future<Session?> session(
    String clubId, {
    required String assignmentId,
    required DateTime date,
    required int week,
    required int day,
  });

  /// Every record of the session [sessionId] of [clubId].
  Future<List<SetRecord>> records(String clubId, String sessionId);
}

class MongoFindSessionStore implements FindSessionStore {
  MongoFindSessionStore(this._db);

  final Db _db;

  @override
  Future<Assignment?> assignment(String clubId, String assignmentId) async {
    final doc = await _db.collection(Colecciones.asignaciones).findOne({
      '_id': assignmentId,
      'clubId': clubId,
    });
    return doc == null ? null : Assignment.fromJson(desdeDocumento(doc));
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
  Future<Session?> session(
    String clubId, {
    required String assignmentId,
    required DateTime date,
    required int week,
    required int day,
  }) async {
    final doc = await _db.collection(Colecciones.sesiones).findOne({
      'clubId': clubId,
      'asignacionId': assignmentId,
      'fecha': aIsoFecha(date),
      'semana': week,
      'dia': day,
    });
    return doc == null ? null : Session.fromJson(desdeDocumento(doc));
  }

  @override
  Future<List<SetRecord>> records(String clubId, String sessionId) async {
    final docs = await _db.collection(Colecciones.registros).find({
      'clubId': clubId,
      'sesionId': sessionId,
    }).toList();
    return [for (final d in docs) SetRecord.fromJson(desdeDocumento(d))];
  }
}
