import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "timers at hand" slice reads and writes.
abstract interface class QuickTimersStore {
  /// [userId]'s choice in [clubId], or null if they never made one.
  Future<QuickTimers?> find(String clubId, String userId);

  /// The ids of every timer [clubId] can use: its own and the platform's.
  Future<Set<String>> timerIds(String clubId);

  /// Replaces that user's choice in that club.
  Future<void> save(QuickTimers quick);
}

class MongoQuickTimersStore implements QuickTimersStore {
  MongoQuickTimersStore(this._db);

  final Db _db;

  static String _id(String clubId, String userId) => '$clubId:$userId';

  @override
  Future<QuickTimers?> find(String clubId, String userId) async {
    final doc = await _db.collection(Colecciones.temporizadoresAMano).findOne({
      '_id': _id(clubId, userId),
      'clubId': clubId,
    });
    return doc == null ? null : QuickTimers.fromJson(desdeDocumento(doc));
  }

  @override
  Future<Set<String>> timerIds(String clubId) async {
    final docs = await _db.collection(Colecciones.temporizadores).find({
      'clubId': {
        r'$in': [clubId, clubPlataforma],
      },
    }).toList();
    return {for (final d in docs) '${d['_id']}'};
  }

  @override
  Future<void> save(QuickTimers quick) async {
    final id = _id(quick.clubId, quick.userId);
    await _db
        .collection(Colecciones.temporizadoresAMano)
        .replaceOne({'_id': id, 'clubId': quick.clubId}, aDocumento(quick.toJson(), id: id), upsert: true);
  }
}
