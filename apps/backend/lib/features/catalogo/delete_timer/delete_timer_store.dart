import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

abstract interface class DeleteTimerStore {
  /// A timer by id if it is visible to [clubId] (base or the club's own), else null.
  Future<Temporizador?> findVisible(String clubId, String id);

  /// Replaces the club's own timer (to archive it); the filter includes `clubId`.
  Future<void> replace(Temporizador timer);

  /// Deletes the club's own timer; the filter includes `clubId`.
  Future<void> delete(String clubId, String id);
}

/// Whether a timer is referenced anywhere (plans, sessions). The question is an interface so E5 (plans)
/// and E7 (records) add their real queries when those collections exist (design.md D11).
abstract interface class TimerUsage {
  Future<bool> isUsed(String clubId, String timerId);
}

/// Until plans and sessions can reference a timer (E5, E7), nothing uses one.
class NoTimerUsageYet implements TimerUsage {
  const NoTimerUsageYet();

  @override
  Future<bool> isUsed(String clubId, String timerId) async => false;
}

class MongoDeleteTimerStore implements DeleteTimerStore {
  MongoDeleteTimerStore(this._db);

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

  @override
  Future<void> delete(String clubId, String id) async {
    await _db.collection(Colecciones.temporizadores).deleteOne({'_id': id, 'clubId': clubId});
  }
}
