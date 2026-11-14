import 'package:maktub_backend/features/sesion/live_tickets.dart';
import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "request a live ticket" slice reads and writes. Every read carries the club id.
abstract interface class RequestLiveTicketStore {
  /// The session [sessionId] of [clubId], or null if the club has none with that id.
  Future<Session?> session(String clubId, String sessionId);

  /// The group that the assignment [assignmentId] of [clubId] runs for, or null if the club has none with that id.
  Future<String?> groupIdOfAssignment(String clubId, String assignmentId);

  /// The athlete ids of the group [groupId] of [clubId]; empty if the group is not in the club.
  Future<List<String>> groupMemberIds(String clubId, String groupId);

  /// The athlete of [clubId] linked to the user [userId], or null if the user is not an athlete there.
  Future<String?> athleteIdOfUser(String clubId, String userId);

  /// Keeps [ticket] under [value] until it is used or expires.
  void saveTicket(String value, LiveTicket ticket, {required DateTime now});
}

class MongoRequestLiveTicketStore implements RequestLiveTicketStore {
  MongoRequestLiveTicketStore(this._db, this._tickets);

  final Db _db;
  final LiveTickets _tickets;

  @override
  Future<Session?> session(String clubId, String sessionId) async {
    final doc = await _db.collection(Colecciones.sesiones).findOne({
      '_id': sessionId,
      'clubId': clubId,
    });
    return doc == null ? null : Session.fromJson(desdeDocumento(doc));
  }

  @override
  Future<String?> groupIdOfAssignment(
    String clubId,
    String assignmentId,
  ) async {
    final doc = await _db.collection(Colecciones.asignaciones).findOne({
      '_id': assignmentId,
      'clubId': clubId,
    });
    return doc == null
        ? null
        : Assignment.fromJson(desdeDocumento(doc)).groupId;
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

  @override
  void saveTicket(String value, LiveTicket ticket, {required DateTime now}) =>
      _tickets.save(value, ticket, now: now);
}
