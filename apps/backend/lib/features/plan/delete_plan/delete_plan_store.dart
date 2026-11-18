import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "delete plan" slice reads and writes. Sessions, set records and block times are never touched.
abstract interface class DeletePlanStore {
  /// Deletes the plan [planId] of [clubId] and every assignment of it, active or ended, of a group or of an
  /// athlete. Returns false, deleting nothing, when the plan does not exist in that club.
  Future<bool> deletePlan(String clubId, String planId);
}

class MongoDeletePlanStore implements DeletePlanStore {
  MongoDeletePlanStore(this._db);

  final Db _db;

  @override
  Future<bool> deletePlan(String clubId, String planId) async {
    final plans = _db.collection(Colecciones.planes);
    if (await plans.findOne({'_id': planId, 'clubId': clubId}) == null) return false;
    // Assignments first: a failure in between leaves a plan without assignments, which a retry finishes,
    // never assignments that point at a plan that is gone.
    await _db.collection(Colecciones.asignaciones).deleteMany({'clubId': clubId, 'planId': planId});
    await plans.deleteOne({'_id': planId, 'clubId': clubId});
    return true;
  }
}
