import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "list plans" slice reads.
abstract interface class ListPlansStore {
  /// Every plan of [clubId] and of no other club.
  Future<List<Plan>> plans(String clubId);
}

class MongoListPlansStore implements ListPlansStore {
  MongoListPlansStore(this._db);

  final Db _db;

  @override
  Future<List<Plan>> plans(String clubId) async {
    final docs = await _db.collection(Colecciones.planes).find({
      'clubId': clubId,
    }).toList();
    return [for (final d in docs) Plan.fromJson(desdeDocumento(d))];
  }
}
