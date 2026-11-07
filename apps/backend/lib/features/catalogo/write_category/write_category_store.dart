import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the category write slice reads and writes. Reads receive the visible ids (`plataforma` plus
/// the club); writes always carry the club id.
abstract interface class WriteCategoryStore {
  /// Categories visible to the club, archived included.
  Future<List<Category>> visible(Set<String> clubIds);

  Future<void> insert(Category category);

  /// Replaces the category with that id **of that club**.
  Future<void> replace(Category category);

  Future<void> delete(String clubId, String id);
}

/// Whether anything refers to a category, so it must be archived instead of deleted (F2 §5).
/// Plans (E5) add their own query when they exist.
abstract interface class CategoryUsage {
  Future<bool> isUsed(String clubId, String categoryId);
}

class MongoWriteCategoryStore implements WriteCategoryStore {
  MongoWriteCategoryStore(this._db);

  final Db _db;

  @override
  Future<List<Category>> visible(Set<String> clubIds) async {
    final docs = await _db.collection(Colecciones.categorias).find({
      'clubId': {r'$in': clubIds.toList()},
    }).toList();
    return [for (final d in docs) Category.fromJson(desdeDocumento(d))];
  }

  @override
  Future<void> insert(Category category) =>
      _db.collection(Colecciones.categorias).insertOne(aDocumento(category.toJson()));

  @override
  Future<void> replace(Category category) => _db.collection(Colecciones.categorias).replaceOne({
    '_id': category.id,
    'clubId': category.clubId,
  }, aDocumento(category.toJson()));

  @override
  Future<void> delete(String clubId, String id) =>
      _db.collection(Colecciones.categorias).deleteOne({'_id': id, 'clubId': clubId});
}

/// Usage known today: an exercise of the club has the category.
class MongoCategoryUsage implements CategoryUsage {
  MongoCategoryUsage(this._db);

  final Db _db;

  @override
  Future<bool> isUsed(String clubId, String categoryId) async =>
      await _db.collection(Colecciones.ejercicios).findOne({'clubId': clubId, 'categorias': categoryId}) != null;
}
