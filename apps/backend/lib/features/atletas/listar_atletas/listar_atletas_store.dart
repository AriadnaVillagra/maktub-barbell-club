import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "list athletes" slice reads.
abstract interface class AthleteListStore {
  /// Every athlete of [clubId] and of no other club.
  Future<List<Atleta>> athletes(String clubId);
}

class MongoAthleteListStore implements AthleteListStore {
  MongoAthleteListStore(this._db);

  final Db _db;

  @override
  Future<List<Atleta>> athletes(String clubId) async {
    final docs = await _db.collection(Colecciones.atletas).find({
      'clubId': clubId,
    }).toList();
    return [for (final d in docs) Atleta.fromJson(desdeDocumento(d))];
  }
}
