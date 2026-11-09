import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "write the session's note" slice reads and writes. Every method carries the club id.
abstract interface class SetSessionNoteStore {
  /// The session [sessionId] of [clubId], or null if the club has none with that id.
  Future<Session?> session(String clubId, String sessionId);

  /// The athlete of [clubId] linked to the user [userId], or null if the user is not an athlete there.
  Future<String?> athleteIdOfUser(String clubId, String userId);

  /// Writes [note] on an existing session, or clears it when null, touching nothing but the note and the
  /// modification audit. Returns the stored session.
  Future<Session> setNote(
    String clubId,
    String sessionId,
    String? note, {
    required String userId,
    required DateTime at,
  });
}

class MongoSetSessionNoteStore implements SetSessionNoteStore {
  MongoSetSessionNoteStore(this._db);

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
  Future<Session> setNote(
    String clubId,
    String sessionId,
    String? note, {
    required String userId,
    required DateTime at,
  }) async {
    final audit = Auditoria.nueva(
      userId,
      ahora: at,
    ).modificada(userId, ahora: at).toJson();
    final result = await _db
        .collection(Colecciones.sesiones)
        .modernFindAndModify(
          query: {'_id': sessionId, 'clubId': clubId},
          update: {
            r'$set': {
              'nota': ?note,
              'auditoria.modificadoPor': audit['modificadoPor'],
              'auditoria.modificadoEn': audit['modificadoEn'],
            },
            if (note == null) r'$unset': {'nota': ''},
          },
          returnNew: true,
        );
    final doc = result.value;
    if (!result.success || doc == null) {
      throw StateError('Setting the session note failed: ${result.errmsg}');
    }
    return Session.fromJson(desdeDocumento(doc));
  }
}
