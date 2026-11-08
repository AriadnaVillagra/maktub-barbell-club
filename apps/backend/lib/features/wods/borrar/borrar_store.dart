import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "delete WoD" slice writes.
abstract interface class DeleteWodStore {
  /// Deletes the WoD [wodId] **of [clubId]**. Returns false if no such WoD exists in that club.
  Future<bool> delete(String clubId, String wodId);
}

class MongoDeleteWodStore implements DeleteWodStore {
  MongoDeleteWodStore(this._db);

  final Db _db;

  @override
  Future<bool> delete(String clubId, String wodId) async {
    final result = await _db.collection(Colecciones.wods).deleteOne({
      '_id': wodId,
      'clubId': clubId,
    });
    return result.nRemoved > 0;
  }
}
