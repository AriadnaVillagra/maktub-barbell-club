import 'package:maktub_backend/features/history/history_view.dart';
import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "athlete's history" slice reads. Every method carries the club id.
abstract interface class ListHistoryStore {
  /// The user id linked to the athlete [athleteId] of [clubId], or null if that athlete is not in the club.
  Future<String?> athleteUserId(String clubId, String athleteId);

  /// Up to [limit] sessions of [clubId] the athlete was present in, dated before [before] (all of them without
  /// it), newest date first.
  Future<List<Session>> sessionsBefore(
    String clubId,
    String athleteId, {
    DateTime? before,
    required int limit,
  });

  /// Every session of [clubId] the athlete was present in on [date].
  Future<List<Session>> sessionsOn(String clubId, String athleteId, DateTime date);

  /// The plans of [clubId] among [planIds], by id. A deleted plan is missing (E8.9).
  Future<Map<String, Plan>> plans(String clubId, Set<String> planIds);

  /// The sets the athlete recorded in the sessions [sessionIds], each with its session id.
  Future<List<({String sessionId, RecordMark mark})>> records(
    String clubId,
    String athleteId,
    List<String> sessionIds,
  );
}

class MongoListHistoryStore implements ListHistoryStore {
  MongoListHistoryStore(this._db);

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
  Future<List<Session>> sessionsBefore(
    String clubId,
    String athleteId, {
    DateTime? before,
    required int limit,
  }) async {
    var query = where.eq('clubId', clubId).eq('presentes', athleteId);
    if (before != null) query = query.lt('fecha', aIsoFecha(before));
    final docs = await _db
        .collection(Colecciones.sesiones)
        .find(query.sortBy('fecha', descending: true).limit(limit))
        .toList();
    return [for (final d in docs) Session.fromJson(desdeDocumento(d))];
  }

  @override
  Future<List<Session>> sessionsOn(String clubId, String athleteId, DateTime date) async {
    final docs = await _db.collection(Colecciones.sesiones).find({
      'clubId': clubId,
      'presentes': athleteId,
      'fecha': aIsoFecha(date),
    }).toList();
    return [for (final d in docs) Session.fromJson(desdeDocumento(d))];
  }

  @override
  Future<Map<String, Plan>> plans(String clubId, Set<String> planIds) async {
    if (planIds.isEmpty) return const {};
    final docs = await _db.collection(Colecciones.planes).find({
      'clubId': clubId,
      '_id': {r'$in': planIds.toList()},
    }).toList();
    return {
      for (final d in docs) '${d['_id']}': Plan.fromJson(desdeDocumento(d)),
    };
  }

  @override
  Future<List<({String sessionId, RecordMark mark})>> records(
    String clubId,
    String athleteId,
    List<String> sessionIds,
  ) async {
    if (sessionIds.isEmpty) return const [];
    final docs = await _db.collection(Colecciones.registros).find(
      where
          .eq('clubId', clubId)
          .oneFrom('sesionId', sessionIds)
          .eq('atletaId', athleteId)
          .fields(['sesionId', 'bloque', 'prescripcion', 'serie', 'hecha', 'estimada']),
    ).toList();
    return [
      for (final r in docs)
        (
          sessionId: '${r['sesionId']}',
          mark: (
            position: (
              block: (r['bloque'] as num).toInt(),
              prescription: (r['prescripcion'] as num).toInt(),
              set: (r['serie'] as num).toInt(),
            ),
            done: r['hecha'] != false,
            estimated: r['estimada'] == true,
          ),
        ),
    ];
  }
}
