import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "athlete's location by date" slice reads. Every method carries the club id.
abstract interface class AthleteLocationStore {
  /// The athlete [athleteId] of [clubId] with the user linked to it (null if none), or null if there is no such
  /// athlete. One read answers both whether it exists and whether it is the caller.
  Future<({String? userId})?> athlete(String clubId, String athleteId);

  /// The active assignments of [clubId] that [athleteId] is or was in, on any date.
  Future<List<Assignment>> activeAssignments(String clubId, String athleteId);

  /// The plans of [clubId] among [planIds] that have a published version.
  Future<Set<String>> publishedPlanIds(String clubId, Set<String> planIds);
}

class MongoAthleteLocationStore implements AthleteLocationStore {
  MongoAthleteLocationStore(this._db);

  final Db _db;

  @override
  Future<({String? userId})?> athlete(String clubId, String athleteId) async {
    final doc = await _db
        .collection(Colecciones.atletas)
        .findOne(where.eq('_id', athleteId).eq('clubId', clubId).fields(['usuarioId']));
    if (doc == null) return null;
    final user = doc['usuarioId'];
    return (userId: user == null ? null : '$user');
  }

  @override
  Future<List<Assignment>> activeAssignments(
    String clubId,
    String athleteId,
  ) async {
    final docs = await _db.collection(Colecciones.asignaciones).find({
      'clubId': clubId,
      'estado': AssignmentStatus.active.cable,
      'atletas.atletaId': athleteId,
    }).toList();
    return [for (final d in docs) Assignment.fromJson(desdeDocumento(d))];
  }

  @override
  Future<Set<String>> publishedPlanIds(
    String clubId,
    Set<String> planIds,
  ) async => {
    for (final d in await _db.collection(Colecciones.planes).find({
      'clubId': clubId,
      '_id': {r'$in': planIds.toList()},
      'publicado': {r'$ne': null},
    }).toList())
      '${d['_id']}',
  };
}
