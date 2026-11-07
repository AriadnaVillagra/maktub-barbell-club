import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the catalog read slice needs. Every method receives the ids whose documents are visible
/// (`plataforma` plus the current club) and must return only documents with one of those `clubId`s.
abstract interface class ReadCatalogStore {
  /// With [categoryId], only exercises that have that category.
  Future<List<Exercise>> exercises(Set<String> clubIds, {String? categoryId});
  Future<List<Category>> categories(Set<String> clubIds);
  Future<List<Temporizador>> timers(Set<String> clubIds);
  Future<List<MuscleGroup>> muscleGroups(Set<String> clubIds);
  Future<List<MovementPattern>> patterns(Set<String> clubIds);
}

class MongoReadCatalogStore implements ReadCatalogStore {
  MongoReadCatalogStore(this._db);

  final Db _db;

  Future<List<Json>> _find(String collection, Set<String> clubIds, [Map<String, dynamic> extra = const {}]) async {
    final docs = await _db.collection(collection).find({
      'clubId': {r'$in': clubIds.toList()},
      ...extra,
    }).toList();
    return [for (final d in docs) desdeDocumento(d)];
  }

  @override
  Future<List<Exercise>> exercises(Set<String> clubIds, {String? categoryId}) async => [
    for (final j in await _find(Colecciones.ejercicios, clubIds, {'categorias': ?categoryId})) Exercise.fromJson(j),
  ];

  @override
  Future<List<Category>> categories(Set<String> clubIds) async => [
    for (final j in await _find(Colecciones.categorias, clubIds)) Category.fromJson(j),
  ];

  @override
  Future<List<Temporizador>> timers(Set<String> clubIds) async => [
    for (final j in await _find(Colecciones.temporizadores, clubIds)) Temporizador.fromJson(j),
  ];

  @override
  Future<List<MuscleGroup>> muscleGroups(Set<String> clubIds) async => [
    for (final j in await _find(Colecciones.gruposMusculares, clubIds)) MuscleGroup.fromJson(j),
  ];

  @override
  Future<List<MovementPattern>> patterns(Set<String> clubIds) async => [
    for (final j in await _find(Colecciones.patrones, clubIds)) MovementPattern.fromJson(j),
  ];
}
