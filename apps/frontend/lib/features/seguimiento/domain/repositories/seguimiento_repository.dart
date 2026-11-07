import 'package:maktub_core/maktub_core.dart';

abstract interface class SeguimientoRepository {
  Future<SeguimientoSnapshot> obtener();

  /// Reemplaza el registro del día y devuelve lo que quedó guardado.
  Future<SesionRegistrada> guardarSesion(SesionRegistrada sesion);
}
