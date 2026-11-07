import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/temporizador/domain/crono.dart';

void main() {
  final t0 = DateTime(2026, 11, 7, 10);
  const descanso = Temporizador(id: 'd', nombre: 'Descanso', tipo: TipoTemporizador.countdown, trabajoSeg: 90);

  test('cuenta contra el reloj, no por ticks', () {
    final crono = Crono.iniciar(descanso, t0)!;
    expect(crono.restantes(t0), 90);
    expect(crono.restantes(t0.add(const Duration(seconds: 60, milliseconds: 100))), 30);
    expect(crono.restantes(t0.add(const Duration(minutes: 5))), 0);
  });

  test('pausa congela lo que queda y al seguir recalcula el fin', () {
    var crono = Crono.iniciar(descanso, t0)!;
    crono = crono.alternarPausa(t0.add(const Duration(seconds: 30)));
    expect(crono.restantes(t0.add(const Duration(minutes: 10))), 60);

    final reanudado = t0.add(const Duration(minutes: 10));
    crono = crono.alternarPausa(reanudado);
    expect(crono.restantes(reanudado.add(const Duration(seconds: 10))), 50);
  });

  test('restar tiempo nunca deja el fin en el pasado', () {
    final crono = Crono.iniciar(descanso, t0)!.sumar(-300, t0);
    expect(crono.restantes(t0), 0);
  });

  test('tabata avanza por fases y termina sin descanso final', () {
    var crono = Crono.iniciar(
      const Temporizador(id: 't', nombre: 'Tabata', tipo: TipoTemporizador.tabata, trabajoSeg: 20, descansoSeg: 10, rondas: 2),
      t0,
    );
    final etiquetas = <String>[];
    while (crono != null) {
      etiquetas.add(crono.fase.etiqueta);
      crono = crono.avanzar(t0);
    }
    expect(etiquetas, ['Trabajo', 'Descanso', 'Trabajo']);
  });

  test('un temporizador sin duración no arranca', () {
    expect(
      Crono.iniciar(const Temporizador(id: 'x', nombre: 'x', tipo: TipoTemporizador.countdown, trabajoSeg: 0), t0),
      isNull,
    );
  });
}
