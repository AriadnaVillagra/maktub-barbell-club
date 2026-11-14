import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the athletes import reads. It never writes: writes go through the E3.2 and E3.3 use cases.
abstract interface class AthleteImportStore {
  /// The athletes of [clubId].
  Future<List<Atleta>> athletes(String clubId);

  /// The `rm` references of [clubId].
  Future<List<Reference>> rms(String clubId);

  /// The fixed weights of [clubId].
  Future<List<FixedWeight>> fixedWeights(String clubId);
}

class MongoAthleteImportStore implements AthleteImportStore {
  MongoAthleteImportStore(this._db);

  final Db _db;

  Future<List<Json>> _find(String collection, Map<String, Object> filter) async => [
    for (final d in await _db.collection(collection).find(filter).toList()) desdeDocumento(d),
  ];

  @override
  Future<List<Atleta>> athletes(String clubId) async => [
    for (final j in await _find(Colecciones.atletas, {'clubId': clubId})) Atleta.fromJson(j),
  ];

  @override
  Future<List<Reference>> rms(String clubId) async => [
    for (final j in await _find(Colecciones.referencias, {'clubId': clubId, 'tipo': ReferenceType.rm.cable}))
      Reference.fromJson(j),
  ];

  @override
  Future<List<FixedWeight>> fixedWeights(String clubId) async => [
    for (final j in await _find(Colecciones.kilajesFijos, {'clubId': clubId})) FixedWeight.fromJson(j),
  ];
}
