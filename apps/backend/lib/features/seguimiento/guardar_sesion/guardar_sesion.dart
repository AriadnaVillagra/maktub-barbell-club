import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart' show Db;

import '../../../infraestructura/http.dart';
import 'guardar_sesion_store.dart';

/// PUT /seguimiento/sesiones — guarda el día de un atleta. Si ya estaba
/// registrado (mismo atleta, plan, ciclo, semana y día), lo reemplaza entero.
Future<Response> guardarSesionEndpoint(RequestContext context) async {
  final sesion = SesionRegistrada.fromJson(await leerCuerpoJson(context.request));
  final caso = GuardarSesion(MongoGuardarSesionStore(context.read<Db>()));
  return Response.json(body: (await caso(sesion)).toJson());
}

class GuardarSesion {
  const GuardarSesion(this._store);

  final GuardarSesionStore _store;

  Future<SesionRegistrada> call(SesionRegistrada sesion) async {
    final errores = sesion.validar();
    if (errores.isNotEmpty) {
      throw ErrorDeSolicitud('Sesión inválida: ${errores.join(', ')}.');
    }

    final (existeAtleta, existePlan) = await (_store.existeAtleta(sesion.atleta), _store.existePlan(sesion.plan)).wait;
    if (!existeAtleta) throw ErrorDeSolicitud.noEncontrado('No existe el atleta "${sesion.atleta}".');
    if (!existePlan) throw ErrorDeSolicitud.noEncontrado('No existe el plan "${sesion.plan}".');

    await _store.reemplazar(sesion);
    return sesion;
  }
}
