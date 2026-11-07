import 'package:maktub_backend/features/seguimiento/guardar_sesion/guardar_sesion.dart';
import 'package:maktub_backend/features/seguimiento/guardar_sesion/guardar_sesion_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

class _StoreFalso implements GuardarSesionStore {
  final guardadas = <String, SesionRegistrada>{};

  @override
  Future<bool> existeAtleta(String id) async => id == 'a1';

  @override
  Future<bool> existePlan(String id) async => id == 'p1';

  @override
  Future<void> reemplazar(SesionRegistrada sesion) async => guardadas[sesion.clave] = sesion;
}

SesionRegistrada _sesion({String atleta = 'a1', String plan = 'p1', int semana = 2, List<FilaRegistro> filas = const []}) =>
    SesionRegistrada(
      atleta: atleta,
      plan: plan,
      ciclo: 1,
      semana: semana,
      dia: 1,
      fecha: DateTime.utc(2026, 11, 9),
      filas: filas,
    );

void main() {
  late _StoreFalso store;
  late GuardarSesion guardar;

  setUp(() {
    store = _StoreFalso();
    guardar = GuardarSesion(store);
  });

  test('guardar dos veces el mismo día reemplaza la sesión', () async {
    await guardar(_sesion(filas: const [FilaRegistro(ejercicio: 'sq', bloque: Bloque.principal, pesoKg: 60)]));
    await guardar(_sesion(filas: const [FilaRegistro(ejercicio: 'sq', bloque: Bloque.principal, pesoKg: 62.5)]));

    expect(store.guardadas, hasLength(1));
    expect(store.guardadas.values.single.filas.single.pesoKg, 62.5);
  });

  test('rechaza una sesión mal formada con 400', () {
    expect(
      () => guardar(_sesion(semana: 5)),
      throwsA(isA<ErrorDeSolicitud>().having((e) => e.estado, 'estado', 400)),
    );
  });

  test('rechaza atleta o plan inexistentes con 404', () async {
    await expectLater(
      guardar(_sesion(atleta: 'zz')),
      throwsA(isA<ErrorDeSolicitud>().having((e) => e.estado, 'estado', 404)),
    );
    await expectLater(
      guardar(_sesion(plan: 'zz')),
      throwsA(isA<ErrorDeSolicitud>().having((e) => e.estado, 'estado', 404)),
    );
    expect(store.guardadas, isEmpty);
  });
}
