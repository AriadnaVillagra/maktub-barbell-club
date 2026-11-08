import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "save plan" slice reads and writes.
abstract interface class SavePlanStore {
  /// The stored plan [planId] of [clubId], or null if it does not exist in that club.
  Future<Plan?> plan(String clubId, String planId);

  /// The exercises visible to [clubId] (platform base plus the club's own), by id.
  Future<Map<String, Exercise>> exercises(String clubId);

  /// Replaces the saved content (name, type, week models, assignment, audit) of the plan with that id **of that
  /// club** in one write, keeping whatever published copy the stored document has. Returns false, and writes nothing, if no such plan exists.
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

  // One document, one `$set` of every field but the published copy: atomic (design D15), and a publish that
  // lands between the read and this write is not undone, because this write never touches `publicado`.
  @override
  Future<bool> replace(Plan plan) async {
    final fields = aDocumento(plan.toJson())
      ..remove('_id')
      ..remove('clubId')
      ..remove('publicado');
    final result = await _db.collection(Colecciones.planes).updateOne({
      '_id': plan.id,
      'clubId': plan.clubId,
    }, {r'$set': fields});
    return result.nMatched > 0;
  }
}
