import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/seguimiento/domain/repositories/seguimiento_repository.dart';

class RepositorioFalso implements SeguimientoRepository {
  RepositorioFalso(this.datos);

  SeguimientoSnapshot datos;
  final guardadas = <SesionRegistrada>[];
  Object? errorAlGuardar;

  @override
  Future<SeguimientoSnapshot> obtener() async => datos;

  @override
  Future<SesionRegistrada> guardarSesion(SesionRegistrada sesion) async {
    if (errorAlGuardar != null) throw errorAlGuardar!;
    guardadas.add(sesion);
    datos = datos.conSesion(sesion);
    return sesion;
  }
}
