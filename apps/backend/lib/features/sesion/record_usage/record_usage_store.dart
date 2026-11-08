import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the record usage slice reads: whether any set record refers to an exercise.
abstract interface class RecordUsageStore {
  /// Whether a record has [exerciseId] as its exercise. Only records of [clubId] count; a null [clubId] means
  /// every club (the question for a platform base exercise, which any club may have trained).
  Future<bool> exerciseInRecords(String? clubId, String exerciseId);
}

class MongoRecordUsageStore implements RecordUsageStore {
  MongoRecordUsageStore(this._db);

  final Db _db;

  @override
  Future<bool> exerciseInRecords(String? clubId, String exerciseId) async {
    final doc = await _db.collection(Colecciones.registros).findOne({
      'clubId': ?clubId,
      'ejercicioId': exerciseId,
    });
    return doc != null;
  }
}
