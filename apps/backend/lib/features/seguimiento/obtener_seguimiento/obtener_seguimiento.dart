import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart' show Db;

import 'obtener_seguimiento_store.dart';

/// GET /seguimiento — todo lo que la vista de seguimiento necesita, en una sola llamada.
Future<Response> obtenerSeguimientoEndpoint(RequestContext context) async {
  final caso = ObtenerSeguimiento(MongoObtenerSeguimientoStore(context.read<Db>()));
  return Response.json(body: (await caso()).toJson());
}

class ObtenerSeguimiento {
  const ObtenerSeguimiento(this._store);

  final ObtenerSeguimientoStore _store;

  Future<SeguimientoSnapshot> call() async {
    final (atletas, rms, ejercicios, temporizadores, wods, plan) = await (
      _store.atletas(),
      _store.rms(),
      _store.ejercicios(),
      _store.temporizadores(),
      _store.wods(),
      _store.planActivo(),
    ).wait;

    final vigentes = rmsVigentes(rms);

    return SeguimientoSnapshot(
      atletas: [
        for (final a in atletas)
          Atleta(id: a.id, nombre: a.nombre, rms: vigentes[a.id] ?? const {}, pesosAccesorios: a.pesosAccesorios),
      ],
      ejercicios: {for (final e in ejercicios) e.id: e},
      temporizadores: {for (final t in temporizadores) t.id: t},
      wods: {for (final w in wods) w.id: w},
      plan: plan,
      sesiones: plan == null ? const [] : await _store.sesionesDelPlan(plan.id),
    );
  }
}

/// El RM más reciente por atleta y básico.
Map<String, Map<Basico, double>> rmsVigentes(List<RegistroRm> rms) {
  final ordenados = [...rms]..sort((a, b) => a.fecha.compareTo(b.fecha));
  final resultado = <String, Map<Basico, double>>{};
  for (final r in ordenados) {
    (resultado[r.atleta] ??= {})[r.basico] = r.kilos;
  }
  return resultado;
}
