import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "publish plan" slice reads and writes.
abstract interface class PublishPlanStore {
  /// The stored plan [planId] of [clubId], or null if it does not exist in that club.
  Future<Plan?> plan(String clubId, String planId);

  /// The exercises visible to [clubId] (platform base plus the club's own), by id.
  Future<Map<String, Exercise>> exercises(String clubId);

  /// Sets the published copy of the plan with that id **of that club** to [copy], in one write, but only if
  /// the plan was not saved since [savedAt] (its `auditoria.modificadoEn`, null if never modified): the copy
  /// was validated against that saved content. Returns false, and writes nothing, if there is no such plan or
  /// it changed meanwhile.
  Future<bool> publish(
    String clubId,
    String planId,
    PublishedPlan copy, {
    required DateTime? savedAt,
  });
}

class MongoPublishPlanStore implements PublishPlanStore {
  MongoPublishPlanStore(this._db);

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

  // One document, one `$set`: the published copy is replaced whole or not at all (design D15). The filter on
  // the modification instant makes a save that slipped in after the read win: the publish then writes nothing.
  // (`null` also matches a missing field.)
  @override
  Future<bool> publish(
    String clubId,
    String planId,
    PublishedPlan copy, {
    required DateTime? savedAt,
  }) async {
    final result = await _db
        .collection(Colecciones.planes)
        .updateOne(
          {
            '_id': planId,
            'clubId': clubId,
            'auditoria.modificadoEn': savedAt?.toUtc().toIso8601String(),
          },
          {
            r'$set': {'publicado': copy.toJson()},
          },
        );
    return result.nMatched > 0;
  }
}
