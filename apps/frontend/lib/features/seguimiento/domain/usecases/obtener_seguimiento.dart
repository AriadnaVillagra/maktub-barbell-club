import 'package:maktub_core/maktub_core.dart';

import '../repositories/seguimiento_repository.dart';

class ObtenerSeguimiento {
  const ObtenerSeguimiento(this._repositorio);

  final SeguimientoRepository _repositorio;

  Future<SeguimientoSnapshot> call() => _repositorio.obtener();
}
