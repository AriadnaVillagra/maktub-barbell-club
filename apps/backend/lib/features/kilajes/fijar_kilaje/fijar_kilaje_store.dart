import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "set a fixed weight" slice reads and writes. Every method carries the club id.
abstract interface class SetFixedWeightStore {
  /// Whether the athlete [athleteId] belongs to [clubId].
  Future<bool> athleteInClub(String clubId, String athleteId);

  /// Whether the exercise exists and is visible to the club (its own or a default one).
  Future<bool> exerciseVisible(String clubId, String exerciseId);

  /// The current fixed weight of the athlete and exercise, if any.
  Future<FixedWeight?> find(String clubId, String athleteId, String exerciseId);

  /// Writes the single current value of the (athlete, exercise) pair, replacing the previous one.
  Future<void> save(FixedWeight weight);
}

class MongoSetFixedWeightStore implements SetFixedWeightStore {
  MongoSetFixedWeightStore(this._db);

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
  Future<FixedWeight?> find(
    String clubId,
    String athleteId,
    String exerciseId,
  ) async {
    final doc = await _db.collection(Colecciones.kilajesFijos).findOne({
      'clubId': clubId,
      'atletaId': athleteId,
      'ejercicioId': exerciseId,
    });
    return doc == null ? null : FixedWeight.fromJson(desdeDocumento(doc));
  }

  @override
  Future<void> save(FixedWeight weight) => _db
      .collection(Colecciones.kilajesFijos)
      .replaceOne(
        {
          'clubId': weight.clubId,
          'atletaId': weight.athleteId,
          'ejercicioId': weight.exerciseId,
        },
        aDocumento(weight.toJson()),
        upsert: true,
      );
}
