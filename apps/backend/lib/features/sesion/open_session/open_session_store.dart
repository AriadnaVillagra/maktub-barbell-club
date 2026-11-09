import 'package:maktub_backend/features/sesion/session_sequence.dart';
import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "open or resume a session" slice reads and writes. Every method carries the club id.
abstract interface class OpenSessionStore {
  /// The assignment [assignmentId] of [clubId], or null if the club has none with that id.
  Future<Assignment?> assignment(String clubId, String assignmentId);

  /// The published version of the plan [planId] of [clubId] (never the draft), or null if it has none.
  Future<PublishedPlan?> publishedPlan(String clubId, String planId);

  /// The athlete ids of the group [groupId] of [clubId]; empty if the group is not in the club.
  Future<List<String>> groupMemberIds(String clubId, String groupId);

  /// The athlete of [clubId] linked to the user [userId], or null if the user is not an athlete there.
  Future<String?> athleteIdOfUser(String clubId, String userId);

  /// The session already stored with the key of [candidate], or null.
  Future<Session?> existing(Session candidate);

  /// Numbers a change of the session itself (who is present) and returns the session with its new number.
  Future<Session> markChanged(String clubId, String sessionId);

  /// Atomically returns the session with the key of [candidate] (club, assignment, date, week and day), inserting
  /// [candidate] if there is none, and adds its present athletes to the ones already there: concurrent opens
  /// end up on one document and none of their athletes is lost.
  Future<Session> openOrResume(Session candidate);

  /// Every record of the session [sessionId] of [clubId].
  Future<List<SetRecord>> records(String clubId, String sessionId);
}

class MongoOpenSessionStore implements OpenSessionStore {
  MongoOpenSessionStore(this._db);

  final Db _db;

  @override
  Future<Assignment?> assignment(String clubId, String assignmentId) async {
    final doc = await _db.collection(Colecciones.asignaciones).findOne({
      '_id': assignmentId,
      'clubId': clubId,
    });
    return doc == null ? null : Assignment.fromJson(desdeDocumento(doc));
  }

  @override
  Future<PublishedPlan?> publishedPlan(String clubId, String planId) async {
    final doc = await _db.collection(Colecciones.planes).findOne({
      '_id': planId,
      'clubId': clubId,
    });
    return doc == null ? null : Plan.fromJson(desdeDocumento(doc)).published;
  }

  @override
  Future<List<String>> groupMemberIds(String clubId, String groupId) async {
    final doc = await _db.collection(Colecciones.grupos).findOne({
      '_id': groupId,
      'clubId': clubId,
    });
    return doc == null
        ? const []
        : AthleteGroup.fromJson(desdeDocumento(doc)).memberIds;
  }

  @override
  Future<String?> athleteIdOfUser(String clubId, String userId) async {
    final doc = await _db.collection(Colecciones.atletas).findOne({
      'clubId': clubId,
      'usuarioId': userId,
    });
    return doc == null ? null : '${doc['_id']}';
  }

  Map<String, dynamic> _keyOf(Session candidate) => {
    'clubId': candidate.clubId,
    'asignacionId': candidate.assignmentId,
    'fecha': aDocumento(candidate.toJson())['fecha'],
    'semana': candidate.week,
    'dia': candidate.day,
  };

  @override
  Future<Session?> existing(Session candidate) async {
    final doc = await _db
        .collection(Colecciones.sesiones)
        .findOne(_keyOf(candidate));
    return doc == null ? null : Session.fromJson(desdeDocumento(doc));
  }

  @override
  Future<Session> markChanged(String clubId, String sessionId) async =>
      updateSessionAsChange(
        _db,
        clubId,
        sessionId,
        await nextSessionSequence(_db, clubId, sessionId),
        const {},
      );

  @override
  Future<Session> openOrResume(Session candidate) async {
    final doc = aDocumento(candidate.toJson());
    final filter = _keyOf(candidate);
    final onInsert = Map<String, dynamic>.of(doc)
      ..removeWhere((key, _) => filter.containsKey(key) || key == 'presentes');
    final stored = await upsertByUniqueKey(
      _db.collection(Colecciones.sesiones),
      filter,
      {
        r'$setOnInsert': onInsert,
        r'$addToSet': {
          'presentes': {r'$each': candidate.presentAthleteIds},
        },
      },
    );
    return Session.fromJson(desdeDocumento(stored));
  }

  @override
  Future<List<SetRecord>> records(String clubId, String sessionId) async {
    final docs = await _db.collection(Colecciones.registros).find({
      'clubId': clubId,
      'sesionId': sessionId,
    }).toList();
    return [for (final d in docs) SetRecord.fromJson(desdeDocumento(d))];
  }
}
