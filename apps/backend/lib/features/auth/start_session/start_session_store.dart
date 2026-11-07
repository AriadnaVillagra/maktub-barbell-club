import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:mongo_dart/mongo_dart.dart';

abstract interface class StartSessionStore {
  Future<void> insert({
    required String id,
    required String userId,
    required String refreshHash,
    required String? device,
    required DateTime createdAt,
    required DateTime expiresAt,
  });
}

class MongoStartSessionStore implements StartSessionStore {
  MongoStartSessionStore(this._db);

  final Db _db;

  @override
  Future<void> insert({
    required String id,
    required String userId,
    required String refreshHash,
    required String? device,
    required DateTime createdAt,
    required DateTime expiresAt,
  }) async {
    await _db.collection(Colecciones.loginSessions).insertOne({
      '_id': id,
      'userId': userId,
      'refreshHash': refreshHash,
      'device': ?device,
      'createdAt': createdAt,
      'lastUsedAt': createdAt,
      'expiresAt': expiresAt,
    });
  }
}
