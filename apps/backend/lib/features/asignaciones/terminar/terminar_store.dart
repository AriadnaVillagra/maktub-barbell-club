import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "end assignment" slice reads and writes.
abstract interface class EndAssignmentStore {
  /// The assignment [assignmentId] of [clubId], or null if the club has no such assignment.
  Future<Assignment?> assignment(String clubId, String assignmentId);

  /// Marks the assignment ended on [endDate], audited as modified by [userId] at [at], in one write, only if it
  /// was not ended already. Returns false, and writes nothing, if there is no such assignment in the club or
  /// it is already ended.
  Future<bool> end(
    String clubId,
    String assignmentId, {
    required DateTime endDate,
    required String userId,
    required DateTime at,
  });
}

class MongoEndAssignmentStore implements EndAssignmentStore {
  MongoEndAssignmentStore(this._db);

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
  Future<bool> end(
    String clubId,
    String assignmentId, {
    required DateTime endDate,
    required String userId,
    required DateTime at,
  }) async {
    final result = await _db
        .collection(Colecciones.asignaciones)
        .updateOne(
          {
            '_id': assignmentId,
            'clubId': clubId,
            'estado': {r'$ne': AssignmentStatus.ended.cable},
          },
          {
            r'$set': {
              'estado': AssignmentStatus.ended.cable,
              'fechaFin': aIsoFecha(endDate),
              'auditoria.modificadoPor': userId,
              'auditoria.modificadoEn': at.toUtc().toIso8601String(),
            },
          },
        );
    return result.nMatched > 0;
  }
}
