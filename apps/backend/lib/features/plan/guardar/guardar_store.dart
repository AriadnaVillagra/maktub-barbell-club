import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "save plan" slice reads and writes.
abstract interface class SavePlanStore {
  /// The stored plan [planId] of [clubId], or null if it does not exist in that club.
  Future<Plan?> plan(String clubId, String planId);

  /// The exercises visible to [clubId] (platform base plus the club's own), by id.
  Future<Map<String, Exercise>> exercises(String clubId);

  /// Replaces the whole plan document with that id **of that club** in one write.
  /// Returns false, and writes nothing, if no such plan exists.
  Future<bool> replace(Plan plan);
}

class MongoSavePlanStore implements SavePlanStore {
  MongoSavePlanStore(this._db);

  final Db _db;

  @override
  Future<Plan?> plan(String clubId, String planId) async {
    final doc = await _db.collection(Colecciones.planes).findOne({
      '_id': planId,
      'clubId': clubId,
    });
    return doc == null ? null : Plan.fromJson(desdeDocumento(doc));
  }

  @override
  Future<Map<String, Exercise>> exercises(String clubId) async {
    final docs = await _db.collection(Colecciones.ejercicios).find({
      'clubId': {
        r'$in': [clubId, clubPlataforma],
      },
    }).toList();
    return {
      for (final d in docs)
        for (final e in [Exercise.fromJson(desdeDocumento(d))]) e.id: e,
    };
  }

  // A single-document replace is atomic: the previous plan or the new one, never a mix (design D15).
  @override
  Future<bool> replace(Plan plan) async {
    final result = await _db.collection(Colecciones.planes).replaceOne({
      '_id': plan.id,
      'clubId': plan.clubId,
    }, aDocumento(plan.toJson()));
    return result.nMatched > 0;
  }
}
