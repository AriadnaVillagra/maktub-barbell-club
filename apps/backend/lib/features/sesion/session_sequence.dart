import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// Applies [update] to the session and returns it as stored.
Future<Json> _updateSession(
  Db db,
  String clubId,
  String sessionId,
  Map<String, dynamic> update,
) async {
  final result = await db
      .collection(Colecciones.sesiones)
      .modernFindAndModify(
        query: {'_id': sessionId, 'clubId': clubId},
        update: update,
        returnNew: true,
      );
  final doc = result.value;
  if (!result.success || doc == null) {
    throw StateError('Updating session $sessionId failed: ${result.errmsg}');
  }
  return desdeDocumento(doc);
}

/// Takes the next change number of the session: the counter lives on the session, so it survives restarts.
Future<int> nextSessionSequence(Db db, String clubId, String sessionId) async =>
    (await _updateSession(db, clubId, sessionId, {
          r'$inc': {'secuencia': 1},
        }))['secuencia']
        as int;

/// Applies [update] to a session whose own state changed as change number [sequence], and returns the session.
Future<Session> updateSessionAsChange(
  Db db,
  String clubId,
  String sessionId,
  int sequence,
  Map<String, dynamic> update,
) async {
  final set = (update[r'$set'] as Map<String, dynamic>?) ?? const {};
  return Session.fromJson(
    await _updateSession(db, clubId, sessionId, {
      ...update,
      r'$set': {...set, 'secuenciaSesion': sequence},
    }),
  );
}
