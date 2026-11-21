import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:mongo_dart/mongo_dart.dart';

abstract interface class PlatformContextStore {
  /// Whether the user exists and is marked as platform admin.
  Future<bool> isPlatformAdmin(String userId);
}

class MongoPlatformContextStore implements PlatformContextStore {
  MongoPlatformContextStore(this._db);

  final Db _db;

  @override
  Future<bool> isPlatformAdmin(String userId) async {
    final doc = await _db
        .collection(Colecciones.usuarios)
        .findOne(where.eq('_id', userId).fields(['esAdminPlataforma']));
    return doc?['esAdminPlataforma'] == true;
  }
}
