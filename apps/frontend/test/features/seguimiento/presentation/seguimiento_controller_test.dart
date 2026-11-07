import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/seguimiento/presentation/controllers/estado_seguimiento.dart';
import 'package:maktub_frontend/features/seguimiento/presentation/controllers/seguimiento_controller.dart';
import 'package:maktub_frontend/features/seguimiento/presentation/providers.dart';

import '../../../datos_de_prueba.dart';
import '../../../repositorio_falso.dart';

void main() {
  late RepositorioFalso repo;
  late ProviderContainer contenedor;

  setUp(() {
    repo = RepositorioFalso(snapshotDePrueba());
    contenedor = ProviderContainer(overrides: [
      seguimientoRepositoryProvider.overrideWithValue(repo),
      hoyProvider.overrideWithValue(() => DateTime.utc(2026, 11, 10)), // ciclo 1, semana 2
    ]);
  });

  tearDown(() => contenedor.dispose());

  Future<SeguimientoListo> listo() async =>
      await contenedor.read(seguimientoControllerProvider.future) as SeguimientoListo;

  SeguimientoController control() => contenedor.read(seguimientoControllerProvider.notifier);

  test('arranca en el ciclo y la semana que tocan por fecha', () async {
    final s = await listo();
    expect((s.ciclo, s.semana, s.dia), (1, 2, 1));
    expect(s.sesion.variante, Variante.carga);
    expect(s.atletaId, 'a1');
  });

  test('cambiar de día no pierde lo cargado en el borrador', () async {
    await listo();
    control().elegirSemana(1);
    control().editarNota(0, 'rodilla');
    control().elegirAtleta('a2');
    control().elegirAtleta('a1');

    final s = await listo();
    expect(s.sesion.items[0].nota, 'rodilla');
  });

  test('guardar envía el día completo y lo marca registrado', () async {
    await listo();
    control().cambiarAjuste(-5);
    await control().guardar();

    final s = await listo();
    expect(repo.guardadas.single.filas.firstWhere((f) => f.ejercicio == 'sq').pct, 80.75);
    expect(s.sesion.registrada, isTrue);
    expect(s.diaRegistrado(2, 1), isTrue);
    expect(s.guardando, isFalse);
  });

  test('si guardar falla, el error sube y el borrador queda', () async {
    await listo();
    repo.errorAlGuardar = Exception('sin red');
    control().editarNota(0, 'no perder');

    await expectLater(control().guardar(), throwsException);

    final s = await listo();
    expect(s.guardando, isFalse);
    expect(s.sesion.items[0].nota, 'no perder');
  });

  test('sin plan activo queda no disponible', () async {
    repo.datos = SeguimientoSnapshot(atletas: snapshotDePrueba().atletas);
    final estado = await contenedor.read(seguimientoControllerProvider.future);
    expect(estado, isA<SeguimientoNoDisponible>());
  });
}
