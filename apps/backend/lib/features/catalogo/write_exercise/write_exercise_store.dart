import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the exercise write slice reads and writes. Reads receive the ids whose documents are visible
/// (`plataforma` plus the club); writes always carry the club id, so nothing outside it is touched.
abstract interface class WriteExerciseStore {
  /// Everything visible to the club (archived included), the base the validations run against.
  Future<CatalogView> view(Set<String> clubIds);

  Future<void> insert(Exercise exercise);

  /// Replaces the exercise with that id **of that club**.
  Future<void> replace(Exercise exercise);

  Future<void> delete(String clubId, String id);
}

/// Whether anything refers to an exercise, so it must be archived instead of deleted (F2 §5,
/// "Archivar, no borrar"). Plans (E5) and records (E7) add their own queries when they exist.
abstract interface class ExerciseUsage {
  Future<bool> isUsed(String clubId, String exerciseId);
}

class MongoWriteExerciseStore implements WriteExerciseStore {
  MongoWriteExerciseStore(this._db);

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
  Future<void> insert(Exercise exercise) =>
      _db.collection(Colecciones.ejercicios).insertOne(aDocumento(exercise.toJson()));

  @override
  Future<void> replace(Exercise exercise) => _db.collection(Colecciones.ejercicios).replaceOne({
    '_id': exercise.id,
    'clubId': exercise.clubId,
  }, aDocumento(exercise.toJson()));

  @override
  Future<void> delete(String clubId, String id) =>
      _db.collection(Colecciones.ejercicios).deleteOne({'_id': id, 'clubId': clubId});
}

/// Usage known today: another exercise of the club suggests it or takes its RM as reference.
class MongoExerciseUsage implements ExerciseUsage {
  MongoExerciseUsage(this._db);

  final Db _db;

  @override
  Future<bool> isUsed(String clubId, String exerciseId) async {
    final doc = await _db.collection(Colecciones.ejercicios).findOne({
      'clubId': clubId,
      r'$or': [
        {'sugerencias': exerciseId},
        {'referencia.ejercicioId': exerciseId},
      ],
    });
    return doc != null;
  }
}
