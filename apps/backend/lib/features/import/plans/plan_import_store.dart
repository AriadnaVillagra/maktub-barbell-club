import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the plan import reads. It never writes: writes go through the plan use cases (E5.2, E5.3, E5.14).
abstract interface class PlanImportStore {
  /// The plans of [clubId] among [ids], by id.
  Future<Map<String, Plan>> plans(String clubId, Set<String> ids);

  /// The exercises visible to [clubId] (default plus its own, archived included).
  Future<List<Exercise>> exercises(String clubId);
}

class MongoPlanImportStore implements PlanImportStore {
  MongoPlanImportStore(this._db);

  final Db _db;

  @override
  Future<Map<String, Plan>> plans(String clubId, Set<String> ids) async {
    final docs = await _db.collection(Colecciones.planes).find({
      'clubId': clubId,
      '_id': {r'$in': ids.toList()},
    }).toList();
    return {
      for (final d in docs)
        for (final p in [Plan.fromJson(desdeDocumento(d))]) p.id: p,
    };
  }

  @override
  Future<List<Exercise>> exercises(String clubId) async {
    final docs = await _db.collection(Colecciones.ejercicios).find({
      'clubId': {
        r'$in': [clubId, clubPlataforma],
      },
    }).toList();
    return [for (final d in docs) Exercise.fromJson(desdeDocumento(d))];
  }
}
