import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// [previousHashes] are the refresh hashes that were valid once and have been rotated out (most recent last, capped).
typedef StoredSession = ({String userId, String refreshHash, List<String> previousHashes, DateTime expiresAt, bool revoked});

/// How many rotated hashes a session remembers to recognise reuse.
const rotatedHashesKept = 20;

abstract interface class RefreshSessionStore {
  Future<StoredSession?> find(String sessionId);

  /// Swaps the refresh hash only if it is still [expectedHash] and the session is not revoked,
  /// in one atomic write, remembering [expectedHash] as rotated. `false` means another refresh got there first.
  Future<bool> rotate(String sessionId, {required String expectedHash, required String newHash, required DateTime expiresAt, required DateTime now});

  Future<void> revoke(String sessionId, DateTime now);
}

class MongoRefreshSessionStore implements RefreshSessionStore {
  MongoRefreshSessionStore(this._db);

  final Db _db;

  DbCollection get _sessions => _db.collection(Colecciones.loginSessions);

  @override
  Future<StoredSession?> find(String sessionId) async {
    final doc = await _sessions.findOne({'_id': sessionId});
    if (doc == null) return null;
    return (
      userId: doc['userId'] as String,
      refreshHash: doc['refreshHash'] as String,
      previousHashes: ((doc['previousHashes'] as List?) ?? const []).cast<String>(),
      expiresAt: (doc['expiresAt'] as DateTime).toUtc(),
      revoked: doc['revokedAt'] != null,
    );
  }

  @override
  Future<bool> rotate(String sessionId, {required String expectedHash, required String newHash, required DateTime expiresAt, required DateTime now}) async {
    final result = await _sessions.updateOne(
      {'_id': sessionId, 'refreshHash': expectedHash, 'revokedAt': null},
      {
        r'$set': {'refreshHash': newHash, 'expiresAt': expiresAt, 'lastUsedAt': now},
        r'$push': {
          'previousHashes': {r'$each': [expectedHash], r'$slice': -rotatedHashesKept},
        },
      },
    );
    return result.nModified == 1;
  }

  @override
  Future<void> revoke(String sessionId, DateTime now) async {
    await _sessions.updateOne(
      {'_id': sessionId, 'revokedAt': null},
      {
        r'$set': {'revokedAt': now},
      },
    );
  }
}
