import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import '../../../infraestructura/mongo.dart';

abstract interface class GuardarSesionStore {
  Future<bool> existeAtleta(String id);
  Future<bool> existePlan(String id);

  /// Upsert por [SesionRegistrada.clave]: guardar dos veces el mismo día no duplica.
  Future<void> reemplazar(SesionRegistrada sesion);
}

class MongoGuardarSesionStore implements GuardarSesionStore {
  const MongoGuardarSesionStore(this._db);

  final Db _db;

  Future<bool> _existe(String coleccion, String id) async =>
      await _db.collection(coleccion).findOne(where.eq('_id', id)) != null;

  @override
  Future<bool> existeAtleta(String id) => _existe(Colecciones.atletas, id);

  @override
  Future<bool> existePlan(String id) => _existe(Colecciones.planes, id);

  @override
  Future<void> reemplazar(SesionRegistrada sesion) async {
    final resultado = await _db.collection(Colecciones.sesiones).replaceOne(
          where.eq('_id', sesion.clave),
          aDocumento(sesion.toJson(), id: sesion.clave),
          upsert: true,
        );
    if (!resultado.isSuccess) {
      throw StateError('Mongo no guardó la sesión ${sesion.clave}: ${resultado.errmsg}');
    }
  }
}
