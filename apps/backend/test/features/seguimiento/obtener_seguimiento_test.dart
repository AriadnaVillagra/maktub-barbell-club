import 'package:maktub_backend/features/seguimiento/obtener_seguimiento/obtener_seguimiento.dart';
import 'package:maktub_backend/features/seguimiento/obtener_seguimiento/obtener_seguimiento_store.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

class _StoreFalso implements ObtenerSeguimientoStore {
  _StoreFalso({this.plan, this.listaRms = const [], this.listaSesiones = const []});

  final Plan? plan;
  final List<RegistroRm> listaRms;
  final List<SesionRegistrada> listaSesiones;
  String? planPedido;

  @override
  Future<List<Atleta>> atletas() async => const [
        Atleta(id: 'a1', nombre: 'Andi', pesosAccesorios: {'curl_barra': 12}),
        Atleta(id: 'a2', nombre: 'Ari'),
      ];

  @override
  Future<List<RegistroRm>> rms() async => listaRms;

  @override
  Future<List<Ejercicio>> ejercicios() async =>
      const [Ejercicio(id: 'sq', nombre: 'Sentadilla', categoria: Categoria.primario, referencia: Basico.sentadilla)];

  @override
  Future<List<Temporizador>> temporizadores() async => const [];

  @override
  Future<List<Wod>> wods() async => const [];

  @override
  Future<Plan?> planActivo() async => plan;

  @override
  Future<List<SesionRegistrada>> sesionesDelPlan(String planId) async {
    planPedido = planId;
    return listaSesiones;
  }
}

void main() {
  test('cada atleta recibe su RM más reciente por básico y conserva sus pesos fijos', () async {
    final store = _StoreFalso(listaRms: [
      RegistroRm(atleta: 'a1', basico: Basico.sentadilla, kilos: 85, fecha: DateTime.utc(2026, 12, 20)),
      RegistroRm(atleta: 'a1', basico: Basico.sentadilla, kilos: 80, fecha: DateTime.utc(2026, 2, 1)),
      RegistroRm(atleta: 'a2', basico: Basico.bench, kilos: 55, fecha: DateTime.utc(2026, 2, 1)),
    ]);

    final snapshot = await ObtenerSeguimiento(store)();

    expect(snapshot.atletas[0].rms, {Basico.sentadilla: 85});
    expect(snapshot.atletas[0].pesosAccesorios, {'curl_barra': 12});
    expect(snapshot.atletas[1].rms, {Basico.bench: 55});
    expect(snapshot.ejercicios.keys, ['sq']);
  });

  test('sin plan activo no busca sesiones', () async {
    final store = _StoreFalso();

    final snapshot = await ObtenerSeguimiento(store)();

    expect(snapshot.plan, isNull);
    expect(snapshot.sesiones, isEmpty);
    expect(store.planPedido, isNull);
  });

  test('con plan activo trae solo las sesiones de ese plan', () async {
    final sesion = SesionRegistrada(atleta: 'a1', plan: 'p1', ciclo: 1, semana: 1, dia: 1, fecha: DateTime.utc(2026, 11, 2));
    final store = _StoreFalso(plan: const Plan(id: 'p1', nombre: 'Plan', activo: true), listaSesiones: [sesion]);

    final snapshot = await ObtenerSeguimiento(store)();

    expect(store.planPedido, 'p1');
    expect(snapshot.sesiones.single.clave, sesion.clave);
  });
}
