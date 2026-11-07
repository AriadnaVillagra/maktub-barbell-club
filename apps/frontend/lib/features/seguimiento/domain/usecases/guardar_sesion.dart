import 'package:maktub_core/maktub_core.dart';

import '../entities/sesion_del_dia.dart';
import '../repositories/seguimiento_repository.dart';
import 'armar_registro.dart';

class GuardarSesion {
  const GuardarSesion(this._repositorio);

  final SeguimientoRepository _repositorio;
  static const _armar = ArmarRegistro();

  Future<SesionRegistrada> call(SesionDelDia sesion, {required String planId, required DateTime fecha, required Equipo equipo}) =>
      _repositorio.guardarSesion(_armar(sesion, planId: planId, fecha: fecha, equipo: equipo));
}
