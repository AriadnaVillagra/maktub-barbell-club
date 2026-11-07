import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

abstract interface class SaveTeamStore {
  /// The club's saved equipment, or null if it never saved one.
  Future<Equipo?> find(String clubId);

  /// Inserts or replaces the club's one equipment (F2 S3).
  Future<void> upsert(Equipo team);
}

class MongoSaveTeamStore implements SaveTeamStore {
  MongoSaveTeamStore(this._db);

  final Db _db;

  @override
  Future<Equipo?> find(String clubId) async {
    final doc = await _db.collection(Colecciones.equipos).findOne({'_id': clubId, 'clubId': clubId});
    return doc == null ? null : Equipo.fromJson(desdeDocumento(doc));
  }

  @override
  Future<void> upsert(Equipo team) async {
    await _db
        .collection(Colecciones.equipos)
        .replaceOne(
          {'_id': team.clubId, 'clubId': team.clubId},
          aDocumento(team.toJson(), id: team.clubId),
          upsert: true,
        );
  }
}
