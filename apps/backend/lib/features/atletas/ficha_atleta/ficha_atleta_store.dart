import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the "athlete sheet" slice reads. Every method carries the club id.
abstract interface class AthleteSheetStore {
  /// The user id linked to the athlete [athleteId] of [clubId], or null if that athlete is not in the club.
  Future<String?> athleteUserId(String clubId, String athleteId);

  /// Every RM entry of the athlete (the full history).
  Future<List<Reference>> references(String clubId, String athleteId);

  /// Every work factor entry of the athlete (the full history).
  Future<List<WorkFactor>> workFactors(String clubId, String athleteId);

  /// The current fixed weights of the athlete, one per exercise.
  Future<List<FixedWeight>> fixedWeights(String clubId, String athleteId);
}

class MongoAthleteSheetStore implements AthleteSheetStore {
  MongoAthleteSheetStore(this._db);

  final Db _db;

  @override
  Future<String?> athleteUserId(String clubId, String athleteId) async {
    final doc = await _db.collection(Colecciones.atletas).findOne({
      '_id': athleteId,
      'clubId': clubId,
    });
    return doc == null ? null : '${doc['usuarioId']}';
  }

  Future<List<Json>> _find(
    String collection,
    String clubId,
    String athleteId,
  ) async {
    final docs = await _db.collection(collection).find({
      'clubId': clubId,
      'atletaId': athleteId,
    }).toList();
    return [for (final d in docs) desdeDocumento(d)];
  }

  @override
  Future<List<Reference>> references(String clubId, String athleteId) async => [
    for (final j in await _find(Colecciones.referencias, clubId, athleteId))
      Reference.fromJson(j),
  ];

  @override
  Future<List<WorkFactor>> workFactors(
    String clubId,
    String athleteId,
  ) async => [
    for (final j in await _find(Colecciones.factoresTrabajo, clubId, athleteId))
      WorkFactor.fromJson(j),
  ];

  @override
  Future<List<FixedWeight>> fixedWeights(
    String clubId,
    String athleteId,
  ) async => [
    for (final j in await _find(Colecciones.kilajesFijos, clubId, athleteId))
      FixedWeight.fromJson(j),
  ];
}
