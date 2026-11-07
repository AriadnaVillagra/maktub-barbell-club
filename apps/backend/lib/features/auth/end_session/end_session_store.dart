import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:mongo_dart/mongo_dart.dart';

abstract interface class EndSessionStore {
  /// Revokes the session only if [refreshHash] is its current refresh hash.
  Future<void> revokeIfCurrent(String sessionId, String refreshHash, DateTime now);
}

class MongoEndSessionStore implements EndSessionStore {
  MongoEndSessionStore(this._db);

  final Db _db;

  @override
  Future<void> revokeIfCurrent(String sessionId, String refreshHash, DateTime now) async {
    await _db.collection(Colecciones.loginSessions).updateOne(
      {'_id': sessionId, 'refreshHash': refreshHash, 'revokedAt': null},
      {
        r'$set': {'revokedAt': now},
      },
    );
  }
}
