import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "read plan" slice reads.
abstract interface class ReadPlanStore {
  /// The plan [planId] of [clubId], or null if it does not exist in that club.
  Future<Plan?> plan(String clubId, String planId);
}

class MongoReadPlanStore implements ReadPlanStore {
  MongoReadPlanStore(this._db);

  final Db _db;

  @override
  Future<Plan?> plan(String clubId, String planId) async {
    final doc = await _db.collection(Colecciones.planes).findOne({
      '_id': planId,
      'clubId': clubId,
    });
    return doc == null ? null : Plan.fromJson(desdeDocumento(doc));
  }
}
