import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "record a block time" slice reads and writes. Every method carries the club id.
abstract interface class RecordBlockTimeStore {
  /// The session [sessionId] of [clubId], or null if the club has none with that id.
  Future<Session?> session(String clubId, String sessionId);

  /// The athlete of [clubId] linked to the user [userId], or null if the user is not an athlete there.
  Future<String?> athleteIdOfUser(String clubId, String userId);

  /// Atomically writes [time] under its id (within its club and session) and returns what is stored. If the id
  /// exists, its creation audit stays and everything else becomes [time]'s. Touches that one document only.
  Future<BlockTime> upsert(BlockTime time);
}

class MongoRecordBlockTimeStore implements RecordBlockTimeStore {
  MongoRecordBlockTimeStore(this._db);

  final Db _db;

  @override
  Future<Session?> session(String clubId, String sessionId) async {
    final doc = await _db.collection(Colecciones.sesiones).findOne({
      '_id': sessionId,
      'clubId': clubId,
    });
    return doc == null ? null : Session.fromJson(desdeDocumento(doc));
  }

  @override
  Future<String?> athleteIdOfUser(String clubId, String userId) async {
    final doc = await _db.collection(Colecciones.atletas).findOne({
      'clubId': clubId,
      'usuarioId': userId,
    });
    return doc == null ? null : '${doc['_id']}';
  }

  @override
  Future<BlockTime> upsert(BlockTime time) async {
    final doc = aDocumento(time.toJson());
    final audit = time.auditoria.toJson();
    final stored = await upsertByUniqueKey(
      _db.collection(Colecciones.tiemposBloque),
      {'_id': doc['_id'], 'clubId': time.clubId, 'sesionId': time.sessionId},
      {
        r'$set': {
          for (final e in doc.entries)
            if (e.key != '_id' &&
                e.key != 'clubId' &&
                e.key != 'sesionId' &&
                e.key != 'auditoria')
              e.key: e.value,
          'auditoria.modificadoPor': audit['modificadoPor'],
          'auditoria.modificadoEn': audit['modificadoEn'],
        },
        r'$setOnInsert': {
          'auditoria.creadoPor': audit['creadoPor'],
          'auditoria.creadoEn': audit['creadoEn'],
        },
        if (time.athleteMode == null) r'$unset': {'modoAtletas': ''},
      },
    );
    return BlockTime.fromJson(desdeDocumento(stored));
  }
}
