import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/temporizador/domain/crono.dart';

void main() {
  final t0 = DateTime(2026, 11, 14, 10);
  const forTime = Temporizador(
    id: 'ft',
    nombre: 'Cronómetro',
    tipo: TipoTemporizador.forTime,
  );

  test('un for time sin tope arranca y cuenta hacia arriba', () {
    final crono = Crono.iniciar(forTime, t0)!;
    expect(crono.abierta, isTrue);
    expect(crono.visibles(t0), 0);
    expect(
      crono.visibles(t0.add(const Duration(seconds: 75, milliseconds: 900))),
      75,
    );
    expect(crono.restantes(t0.add(const Duration(minutes: 5))), 0);
  });

  test('pausar congela lo que lleva y seguir lo retoma desde ahí', () {
    var crono = Crono.iniciar(forTime, t0)!;
    crono = crono.alternarPausa(t0.add(const Duration(seconds: 30)));
    expect(crono.visibles(t0.add(const Duration(minutes: 10))), 30);

    final reanudado = t0.add(const Duration(minutes: 10));
    crono = crono.alternarPausa(reanudado);
    expect(crono.visibles(reanudado.add(const Duration(seconds: 15))), 45);
  });

  test('sumar tiempo no cambia una fase abierta', () {
    final crono = Crono.iniciar(forTime, t0)!;
    expect(identical(crono.sumar(30, t0), crono), isTrue);
  });

  test(
    'un for time con tope es una cuenta regresiva que se puede terminar antes',
    () {
      final crono = Crono.iniciar(
        const Temporizador(
          id: 'ft',
          nombre: 'FT',
          tipo: TipoTemporizador.forTime,
          limiteSeg: 600,
        ),
        t0,
      )!;
      expect(crono.abierta, isFalse);
      expect(crono.sePuedeTerminar, isTrue);
      final tarde = t0.add(const Duration(seconds: 200));
      expect(crono.restantes(tarde), 400);
      expect(crono.transcurridos(tarde), 200);
    },
  );

  test('con series, terminar la fase abierta pasa al descanso y después a la serie siguiente', () {
    var crono = Crono.iniciar(
      const Temporizador(
        id: 'ft',
        nombre: 'FT',
        tipo: TipoTemporizador.forTime,
        series: 2,
        descansoSeriesSeg: 60,
      ),
      t0,
    )!;
    final a = t0.add(const Duration(seconds: 90));
    crono = crono.avanzar(a)!;
    expect(crono.fase.etiqueta, 'Descanso entre series');
    expect(crono.restantes(a), 60);
    final b = a.add(const Duration(seconds: 60));
    crono = crono.avanzar(b)!;
    expect(crono.abierta, isTrue);
    expect(crono.visibles(b.add(const Duration(seconds: 5))), 5);
    expect(crono.avanzar(b), isNull);
  });

  test('Death By se puede terminar y no tiene cantidad fija de rondas', () {
    final crono = Crono.iniciar(
      const Temporizador(
        id: 'db',
        nombre: 'Death By',
        tipo: TipoTemporizador.emom,
        trabajoSeg: 60,
        deathBy: true,
      ),
      t0,
    )!;
    expect(crono.fase.rondas, 0);
    expect(crono.sePuedeTerminar, isTrue);
  });

  test('una cuenta regresiva no se puede terminar antes', () {
    final crono = Crono.iniciar(
      const Temporizador(
        id: 'd',
        nombre: 'Descanso',
        tipo: TipoTemporizador.countdown,
        trabajoSeg: 90,
      ),
      t0,
    )!;
    expect(crono.sePuedeTerminar, isFalse);
  });
}
