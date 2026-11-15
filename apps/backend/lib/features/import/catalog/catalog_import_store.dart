import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the catalog import reads. It never writes: writes go through the catalog and WoD use cases.
abstract interface class CatalogImportStore {
  /// Exercises and categories of [clubIds] (archived included).
  Future<CatalogView> view(Set<String> clubIds);

  /// Timers of [clubIds].
  Future<List<Temporizador>> timers(Set<String> clubIds);

  /// The WoD library of [clubId] and of no other club.
  Future<List<Wod>> wods(String clubId);
}

class MongoCatalogImportStore implements CatalogImportStore {
  MongoCatalogImportStore(this._db);

  final Db _db;

  Future<List<Json>> _find(String collection, Set<String> clubIds) async {
    final docs = await _db.collection(collection).find({
      'clubId': {r'$in': clubIds.toList()},
    }).toList();
    return [for (final d in docs) desdeDocumento(d)];
  }

  @override
  Future<CatalogView> view(Set<String> clubIds) async => CatalogView.of(
    exercises: [for (final j in await _find(Colecciones.ejercicios, clubIds)) Exercise.fromJson(j)],
    categories: [for (final j in await _find(Colecciones.categorias, clubIds)) Category.fromJson(j)],
    groups: [for (final j in await _find(Colecciones.gruposMusculares, clubIds)) MuscleGroup.fromJson(j)],
    patterns: [for (final j in await _find(Colecciones.patrones, clubIds)) MovementPattern.fromJson(j)],
  );

  @override
  Future<List<Temporizador>> timers(Set<String> clubIds) async => [
    for (final j in await _find(Colecciones.temporizadores, clubIds)) Temporizador.fromJson(j),
  ];

  @override
  Future<List<Wod>> wods(String clubId) async => [
    for (final j in await _find(Colecciones.wods, {clubId})) Wod.fromJson(j),
  ];
}
