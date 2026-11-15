import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "athlete's location by date" slice reads. Every method carries the club id.
abstract interface class AthleteLocationStore {
  /// Whether the athlete [athleteId] exists in [clubId].
  Future<bool> athleteExists(String clubId, String athleteId);

  /// The athlete of [clubId] linked to the user [userId], or null if the user is not an athlete there.
  Future<String?> athleteIdOfUser(String clubId, String userId);

  /// The groups of [clubId] that [athleteId] is a member of.
  Future<Set<String>> groupIdsOf(String clubId, String athleteId);

  /// The active assignments of [clubId] of any of [groupIds] or of [athleteId] itself.
  Future<List<Assignment>> activeAssignments(
    String clubId, {
    required Set<String> groupIds,
    required String athleteId,
  });

  /// The plans of [clubId] among [planIds] that have a published version.
  Future<Set<String>> publishedPlanIds(String clubId, Set<String> planIds);
}

class MongoAthleteLocationStore implements AthleteLocationStore {
  MongoAthleteLocationStore(this._db);

  final Db _db;

  @override
  Future<bool> athleteExists(String clubId, String athleteId) async =>
      await _db.collection(Colecciones.atletas).findOne({
        '_id': athleteId,
        'clubId': clubId,
      }) !=
      null;

  @override
  Future<String?> athleteIdOfUser(String clubId, String userId) async {
    final doc = await _db.collection(Colecciones.atletas).findOne({
      'clubId': clubId,
      'usuarioId': userId,
    });
    return doc == null ? null : '${doc['_id']}';
  }

  @override
  Future<Set<String>> groupIdsOf(String clubId, String athleteId) async => {
    for (final d
        in await _db.collection(Colecciones.grupos).find({
          'clubId': clubId,
          'miembros': athleteId,
        }).toList())
      '${d['_id']}',
  };

  @override
  Future<List<Assignment>> activeAssignments(
    String clubId, {
    required Set<String> groupIds,
    required String athleteId,
  }) async {
    final docs = await _db.collection(Colecciones.asignaciones).find({
      'clubId': clubId,
      'estado': AssignmentStatus.active.cable,
      r'$or': [
        {
          'grupoId': {r'$in': groupIds.toList()},
        },
        {'atletaId': athleteId},
      ],
    }).toList();
    return [for (final d in docs) Assignment.fromJson(desdeDocumento(d))];
  }

  @override
  Future<Set<String>> publishedPlanIds(
    String clubId,
    Set<String> planIds,
  ) async => {
    for (final d
        in await _db.collection(Colecciones.planes).find({
          'clubId': clubId,
          '_id': {r'$in': planIds.toList()},
          'publicado': {r'$ne': null},
        }).toList())
      '${d['_id']}',
  };
}
