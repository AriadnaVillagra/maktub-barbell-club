import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

abstract interface class WhoAmIStore {
  Future<Usuario?> findUser(String userId);

  /// Only memberships with state `activa`.
  Future<List<Membresia>> activeMemberships(String userId);

  Future<List<Club>> clubsByIds(Set<String> clubIds);
}

class MongoWhoAmIStore implements WhoAmIStore {
  MongoWhoAmIStore(this._db);

  final Db _db;

  @override
  Future<Usuario?> findUser(String userId) async {
    // Credentials (Google sub, password hash) live in the same document: never project them out of here.
    final doc = await _db.collection(Colecciones.usuarios).findOne({'_id': userId});
    return doc == null ? null : Usuario.fromJson(desdeDocumento(doc));
  }

  @override
  Future<List<Membresia>> activeMemberships(String userId) async {
    final docs = await _db
        .collection(Colecciones.membresias)
        .find({'usuarioId': userId, 'estado': EstadoMembresia.activa.cable})
        .toList();
    return [for (final d in docs) Membresia.fromJson(desdeDocumento(d))];
  }

  @override
  Future<List<Club>> clubsByIds(Set<String> clubIds) async {
    if (clubIds.isEmpty) return [];
    final docs = await _db.collection(Colecciones.clubes).find({
      '_id': {r'$in': clubIds.toList()},
    }).toList();
    return [for (final d in docs) Club.fromJson(desdeDocumento(d))];
  }
}
