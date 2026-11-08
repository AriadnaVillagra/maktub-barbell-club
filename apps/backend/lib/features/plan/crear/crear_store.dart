import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "create plan" slice writes.
abstract interface class CreatePlanStore {
  /// Adds a new plan document. The plan carries its own `clubId`.
  Future<void> insert(Plan plan);
}

class MongoCreatePlanStore implements CreatePlanStore {
  MongoCreatePlanStore(this._db);

  final Db _db;

  @override
  Future<void> insert(Plan plan) =>
      _db.collection(Colecciones.planes).insertOne(aDocumento(plan.toJson()));
}
