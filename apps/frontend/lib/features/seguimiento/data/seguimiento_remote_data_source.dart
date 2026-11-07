import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/cliente_api.dart';

class SeguimientoRemoteDataSource {
  const SeguimientoRemoteDataSource(this._api);

  final ClienteApi _api;

  Future<SeguimientoSnapshot> obtener() async => SeguimientoSnapshot.fromJson(await _api.get('/seguimiento'));

  Future<SesionRegistrada> guardarSesion(SesionRegistrada sesion) async =>
      SesionRegistrada.fromJson(await _api.put('/seguimiento/sesiones', sesion.toJson()));
}
