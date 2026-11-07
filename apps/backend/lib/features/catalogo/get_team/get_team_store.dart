import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

abstract interface class GetTeamStore {
  /// The club's saved equipment, or null if it never saved one.
  Future<Equipo?> find(String clubId);
}

class MongoGetTeamStore implements GetTeamStore {
  MongoGetTeamStore(this._db);

  final Db _db;

  @override
  Future<Equipo?> find(String clubId) async {
    final doc = await _db.collection(Colecciones.equipos).findOne({'_id': clubId, 'clubId': clubId});
    return doc == null ? null : Equipo.fromJson(desdeDocumento(doc));
  }
}
