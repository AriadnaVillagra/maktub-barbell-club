import 'package:maktub_core/maktub_core.dart';

import '../domain/repositories/seguimiento_repository.dart';
import 'seguimiento_remote_data_source.dart';

/// Hoy solo remoto. Acá entraría una caché local para usar la app sin señal en el gimnasio.
class SeguimientoRepositoryImpl implements SeguimientoRepository {
  const SeguimientoRepositoryImpl(this._remoto);

  final SeguimientoRemoteDataSource _remoto;

  @override
  Future<SeguimientoSnapshot> obtener() => _remoto.obtener();

  @override
  Future<SesionRegistrada> guardarSesion(SesionRegistrada sesion) => _remoto.guardarSesion(sesion);
}
