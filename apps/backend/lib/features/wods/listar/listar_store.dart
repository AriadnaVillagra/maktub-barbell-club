import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "list WoDs" slice reads.
abstract interface class ListWodsStore {
  /// Every WoD of [clubId] and of no other club.
  Future<List<Wod>> wods(String clubId);
}

class MongoListWodsStore implements ListWodsStore {
  MongoListWodsStore(this._db);

  final Db _db;

  @override
  Future<List<Wod>> wods(String clubId) async {
    final docs = await _db.collection(Colecciones.wods).find({
      'clubId': clubId,
    }).toList();
    return [for (final d in docs) Wod.fromJson(desdeDocumento(d))];
  }
}
