import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "set the athletes of an assignment" slice reads and writes.
abstract interface class SetAssignmentAthletesStore {
  /// The assignment [assignmentId] of [clubId], or null if the club has no such assignment.
  Future<Assignment?> assignment(String clubId, String assignmentId);

  /// Whether every one of [athleteIds] is an athlete of [clubId].
  Future<bool> athletesExist(String clubId, Set<String> athleteIds);

  /// Replaces the members of [current] with [members], audited as modified by [userId] at [at], in one write, only
  /// if the assignment is not ended and its members are still those of [current]. Returns false, and writes
  /// nothing, otherwise.
  Future<bool> replaceMembers(
    Assignment current,
    List<AssignmentMember> members, {
    required String userId,
    required DateTime at,
  });
}

class MongoSetAssignmentAthletesStore implements SetAssignmentAthletesStore {
  MongoSetAssignmentAthletesStore(this._db);

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
  Future<bool> athletesExist(String clubId, Set<String> athleteIds) async {
    final found = await _db.collection(Colecciones.atletas).find({
      'clubId': clubId,
      '_id': {r'$in': athleteIds.toList()},
    }).toList();
    return found.length == athleteIds.length;
  }

  // Two coaches editing at once cannot lose each other's change: the write matches the members it read.
  @override
  Future<bool> replaceMembers(
    Assignment current,
    List<AssignmentMember> members, {
    required String userId,
    required DateTime at,
  }) async {
    final result = await _db
        .collection(Colecciones.asignaciones)
        .updateOne(
          {
            '_id': current.id,
            'clubId': current.clubId,
            'estado': {r'$ne': AssignmentStatus.ended.cable},
            'atletas': [for (final m in current.members) m.toJson()],
          },
          {
            r'$set': {
              'atletas': [for (final m in members) m.toJson()],
              'auditoria.modificadoPor': userId,
              'auditoria.modificadoEn': at.toUtc().toIso8601String(),
            },
          },
        );
    return result.nMatched > 0;
  }
}
