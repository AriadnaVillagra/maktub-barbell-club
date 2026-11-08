import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "register an RM" slice reads and writes. Every method carries the club id.
abstract interface class RegisterRmStore {
  /// Whether the athlete [athleteId] belongs to [clubId].
  Future<bool> athleteInClub(String clubId, String athleteId);

  /// Whether the exercise exists and is visible to the club (its own or a default one).
  Future<bool> exerciseVisible(String clubId, String exerciseId);

  /// The only write: adds one entry to the athlete's history.
  Future<void> insert(Reference reference);
}

class MongoRegisterRmStore implements RegisterRmStore {
  MongoRegisterRmStore(this._db);

  final Db _db;

  @override
  Future<bool> athleteInClub(String clubId, String athleteId) async =>
      await _db.collection(Colecciones.atletas).findOne({
        '_id': athleteId,
        'clubId': clubId,
      }) !=
      null;

  @override
  Future<bool> exerciseVisible(String clubId, String exerciseId) async =>
      await _db.collection(Colecciones.ejercicios).findOne({
        '_id': exerciseId,
        'clubId': {
          r'$in': [clubId, clubPlataforma],
        },
      }) !=
      null;

  @override
  Future<void> insert(Reference reference) => _db
      .collection(Colecciones.referencias)
      .insertOne(aDocumento(reference.toJson()));
}
