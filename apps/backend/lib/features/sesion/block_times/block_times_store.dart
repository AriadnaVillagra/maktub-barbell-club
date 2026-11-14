import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "block times of a session" slice reads. Every method carries the club id.
abstract interface class BlockTimesStore {
  /// The session [sessionId] of [clubId], or null if the club has none with that id.
  Future<Session?> session(String clubId, String sessionId);

  /// The athlete of [clubId] linked to the user [userId], or null if the user is not an athlete there.
  Future<String?> athleteIdOfUser(String clubId, String userId);

  /// The block times of the session, oldest start first.
  Future<List<BlockTime>> timesOf(String clubId, String sessionId);
}

class MongoBlockTimesStore implements BlockTimesStore {
  MongoBlockTimesStore(this._db);

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
  Future<String?> athleteIdOfUser(String clubId, String userId) async {
    final doc = await _db.collection(Colecciones.atletas).findOne({
      'clubId': clubId,
      'usuarioId': userId,
    });
    return doc == null ? null : '${doc['_id']}';
  }

  @override
  Future<List<BlockTime>> timesOf(String clubId, String sessionId) async {
    final docs = await _db.collection(Colecciones.tiemposBloque).find({
      'clubId': clubId,
      'sesionId': sessionId,
    }).toList();
    return [for (final d in docs) BlockTime.fromJson(desdeDocumento(d))]
      ..sort((a, b) => a.start.compareTo(b.start));
  }
}
