import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

abstract interface class ListAllClubsStore {
  /// Every club of type `club` (never the personal ones), by name.
  Future<List<Club>> clubs();
}

class MongoListAllClubsStore implements ListAllClubsStore {
  MongoListAllClubsStore(this._db);

  final Db _db;

  @override
  Future<List<Club>> clubs() async {
    final docs = await _db
        .collection(Colecciones.clubes)
        .find(where.eq('tipo', TipoClub.club.cable).sortBy('nombre'))
        .toList();
    return [for (final d in docs) Club.fromJson(desdeDocumento(d))];
  }
}
