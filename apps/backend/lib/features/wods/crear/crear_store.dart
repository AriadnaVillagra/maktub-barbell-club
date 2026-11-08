import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "create WoD" slice writes.
abstract interface class CreateWodStore {
  /// Adds a new WoD document. The WoD carries its own `clubId`.
  Future<void> insert(Wod wod);
}

class MongoCreateWodStore implements CreateWodStore {
  MongoCreateWodStore(this._db);

  final Db _db;

  @override
  Future<void> insert(Wod wod) =>
      _db.collection(Colecciones.wods).insertOne(aDocumento(wod.toJson()));
}
