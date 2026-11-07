import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

abstract interface class CreateTimerStore {
  Future<void> insert(Temporizador timer);
}

class MongoCreateTimerStore implements CreateTimerStore {
  MongoCreateTimerStore(this._db);

  final Db _db;

  @override
  Future<void> insert(Temporizador timer) async {
    await _db.collection(Colecciones.temporizadores).insertOne(aDocumento(timer.toJson()));
  }
}
