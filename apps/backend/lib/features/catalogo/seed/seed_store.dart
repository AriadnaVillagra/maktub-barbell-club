import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// What the base catalog seed reads and writes: documents of the `plataforma` club, by collection
/// and id. Nothing else, and never modifies or deletes an existing document.
abstract interface class SeedStore {
  /// Base documents of that collection (JSON with `id`, as the domain sees them), by id.
  Future<Map<String, Json>> baseDocuments(String collection);

  Future<void> insert(String collection, Json json);
}

class MongoSeedStore implements SeedStore {
  MongoSeedStore(this._db);

  final Db _db;

  @override
  Future<Map<String, Json>> baseDocuments(String collection) async {
    final docs = await _db.collection(collection).find({'clubId': clubPlataforma}).toList();
    return {for (final d in docs) '${d['_id']}': desdeDocumento(d)};
  }

  @override
  Future<void> insert(String collection, Json json) =>
      _db.collection(collection).insertOne(aDocumento(json));
}
