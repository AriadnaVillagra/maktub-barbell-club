import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "save WoD" slice reads and writes.
abstract interface class SaveWodStore {
  /// The stored WoD [wodId] of [clubId], or null if it does not exist in that club.
  Future<Wod?> wod(String clubId, String wodId);

  /// Replaces the WoD with that id **of that club** in one write. Returns false, and writes nothing, if none.
  Future<bool> replace(Wod wod);
}

class MongoSaveWodStore implements SaveWodStore {
  MongoSaveWodStore(this._db);

  final Db _db;

  @override
  Future<Wod?> wod(String clubId, String wodId) async {
    final doc = await _db.collection(Colecciones.wods).findOne({
      '_id': wodId,
      'clubId': clubId,
    });
    return doc == null ? null : Wod.fromJson(desdeDocumento(doc));
  }

  @override
  Future<bool> replace(Wod wod) async {
    final result = await _db.collection(Colecciones.wods).replaceOne({
      '_id': wod.id,
      'clubId': wod.clubId,
    }, aDocumento(wod.toJson()));
    return result.nMatched > 0;
  }
}
