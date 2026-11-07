import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import '../../../infraestructura/mongo.dart';

/// Un RM medido. La colección guarda el historial; el vigente es el más reciente.
class RegistroRm {
  const RegistroRm({required this.atleta, required this.basico, required this.kilos, required this.fecha});

  final String atleta;
  final Basico basico;
  final double kilos;
  final DateTime fecha;
}

/// Lecturas que necesita este slice, y solo estas.
abstract interface class ObtenerSeguimientoStore {
  Future<List<Atleta>> atletas();
  Future<List<RegistroRm>> rms();
  Future<List<Ejercicio>> ejercicios();
  Future<List<Temporizador>> temporizadores();
  Future<List<Wod>> wods();
  Future<Plan?> planActivo();
  Future<List<SesionRegistrada>> sesionesDelPlan(String planId);
}

class MongoObtenerSeguimientoStore implements ObtenerSeguimientoStore {
  const MongoObtenerSeguimientoStore(this._db);

  final Db _db;

  Future<List<T>> _todos<T>(String coleccion, T Function(Json) desde, [SelectorBuilder? filtro]) async {
    final docs = await _db.collection(coleccion).find(filtro).toList();
    return [for (final d in docs) desde(desdeDocumento(d))];
  }

  @override
  Future<List<Atleta>> atletas() => _todos(Colecciones.atletas, Atleta.fromJson, where.sortBy('_id'));

  @override
  Future<List<RegistroRm>> rms() => _todos(
        Colecciones.rms,
        (j) => RegistroRm(
          atleta: '${j['atleta']}',
          basico: Basico.desdeCable(j['basico']),
          kilos: (j['kilos'] as num).toDouble(),
          fecha: desdeIsoFecha('${j['fecha']}'),
        ),
      );

  @override
  Future<List<Ejercicio>> ejercicios() => _todos(Colecciones.ejercicios, Ejercicio.fromJson);

  @override
  Future<List<Temporizador>> temporizadores() => _todos(Colecciones.temporizadores, Temporizador.fromJson);

  @override
  Future<List<Wod>> wods() => _todos(Colecciones.wods, Wod.fromJson);

  @override
  Future<Plan?> planActivo() async {
    final doc = await _db.collection(Colecciones.planes).findOne(where.eq('activo', true));
    return doc == null ? null : Plan.fromJson(desdeDocumento(doc));
  }

  @override
  Future<List<SesionRegistrada>> sesionesDelPlan(String planId) =>
      _todos(Colecciones.sesiones, SesionRegistrada.fromJson, where.eq('plan', planId));
}
