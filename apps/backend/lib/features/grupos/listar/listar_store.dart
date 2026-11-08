import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "list groups" slice reads.
abstract interface class ListGroupsStore {
  /// Every group of [clubId] and of no other club.
  Future<List<AthleteGroup>> groups(String clubId);
}

class MongoListGroupsStore implements ListGroupsStore {
  MongoListGroupsStore(this._db);

  final Db _db;

  @override
  Future<List<AthleteGroup>> groups(String clubId) async {
    final docs = await _db.collection(Colecciones.grupos).find({
      'clubId': clubId,
    }).toList();
    return [for (final d in docs) AthleteGroup.fromJson(desdeDocumento(d))];
  }
}
