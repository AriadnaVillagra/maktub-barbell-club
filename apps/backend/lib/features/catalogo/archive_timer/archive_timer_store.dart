import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

abstract interface class ArchiveTimerStore {
  /// A timer by id if it is visible to [clubId] (base or the club's own), else null.
  Future<Temporizador?> findVisible(String clubId, String id);

  /// Replaces the club's own timer; the filter includes `clubId`.
  Future<void> replace(Temporizador timer);
}

class MongoArchiveTimerStore implements ArchiveTimerStore {
  MongoArchiveTimerStore(this._db);

  final Db _db;

  @override
  Future<Temporizador?> findVisible(String clubId, String id) async {
    final doc = await _db.collection(Colecciones.temporizadores).findOne({
      '_id': id,
      'clubId': {
        r'$in': [clubId, clubPlataforma],
      },
    });
    return doc == null ? null : Temporizador.fromJson(desdeDocumento(doc));
  }

  @override
  Future<void> replace(Temporizador timer) async {
    await _db.collection(Colecciones.temporizadores).replaceOne({
      '_id': timer.id,
      'clubId': timer.clubId,
    }, aDocumento(timer.toJson()));
  }
}
