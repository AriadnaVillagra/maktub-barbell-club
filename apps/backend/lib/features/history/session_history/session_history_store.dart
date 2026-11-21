import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "one session of an athlete's history" slice reads. Every method carries the club id.
abstract interface class SessionHistoryStore {
  /// The user id linked to the athlete [athleteId] of [clubId], or null if that athlete is not in the club.
  Future<String?> athleteUserId(String clubId, String athleteId);

  /// The session [sessionId] of [clubId], or null if the club has none with that id.
  Future<Session?> session(String clubId, String sessionId);

  /// The plan [planId] of [clubId], or null if it was deleted (E8.9).
  Future<Plan?> plan(String clubId, String planId);

  /// The sets the athlete recorded in the session.
  Future<List<SetRecord>> records(String clubId, String sessionId, String athleteId);

  /// The block times of the session that the athlete took part in.
  Future<List<BlockTime>> blockTimes(String clubId, String sessionId, String athleteId);

  /// Names of the exercises [exerciseIds] the club sees (its own and the default catalog's), by id.
  Future<Map<String, String>> exerciseNames(String clubId, Set<String> exerciseIds);
}

class MongoSessionHistoryStore implements SessionHistoryStore {
  MongoSessionHistoryStore(this._db);

  final Db _db;

  @override
  Future<String?> athleteUserId(String clubId, String athleteId) async {
    final doc = await _db.collection(Colecciones.atletas).findOne({
      '_id': athleteId,
      'clubId': clubId,
    });
    return doc == null ? null : '${doc['usuarioId']}';
  }

  @override
  Future<Session?> session(String clubId, String sessionId) async {
    final doc = await _db.collection(Colecciones.sesiones).findOne({
      '_id': sessionId,
      'clubId': clubId,
    });
    return doc == null ? null : Session.fromJson(desdeDocumento(doc));
  }

  @override
  Future<Plan?> plan(String clubId, String planId) async {
    final doc = await _db.collection(Colecciones.planes).findOne({
      '_id': planId,
      'clubId': clubId,
    });
    return doc == null ? null : Plan.fromJson(desdeDocumento(doc));
  }

  @override
  Future<List<SetRecord>> records(String clubId, String sessionId, String athleteId) async {
    final docs = await _db.collection(Colecciones.registros).find({
      'clubId': clubId,
      'sesionId': sessionId,
      'atletaId': athleteId,
    }).toList();
    return [for (final d in docs) SetRecord.fromJson(desdeDocumento(d))];
  }

  @override
  Future<List<BlockTime>> blockTimes(String clubId, String sessionId, String athleteId) async {
    final docs = await _db.collection(Colecciones.tiemposBloque).find({
      'clubId': clubId,
      'sesionId': sessionId,
      'atletaIds': athleteId,
    }).toList();
    return [for (final d in docs) BlockTime.fromJson(desdeDocumento(d))];
  }

  @override
  Future<Map<String, String>> exerciseNames(String clubId, Set<String> exerciseIds) async {
    if (exerciseIds.isEmpty) return const {};
    final docs = await _db.collection(Colecciones.ejercicios).find(
      where
          .oneFrom('clubId', [clubId, clubPlataforma])
          .oneFrom('_id', exerciseIds.toList())
          .fields(['nombre']),
    ).toList();
    return {for (final d in docs) '${d['_id']}': '${d['nombre']}'};
  }
}
