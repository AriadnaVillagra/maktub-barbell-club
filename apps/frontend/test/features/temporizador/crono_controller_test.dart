import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/temporizador/presentation/controllers/crono_controller.dart';
import 'package:maktub_frontend/features/temporizador/presentation/providers.dart';

import 'timer_fakes.dart';

const _tick = 880.0;
const _phase = 660.0;
const _end = 990.0;

class _Harness {
  _Harness(this.tester, FakeTimerPlatform platform)
    : container = ProviderContainer(
        overrides: [timerPlatformProvider.overrideWithValue(platform)],
      ) {
    control = container.read(cronoControllerProvider.notifier)
      ..ahora = () => clock;
  }

  final WidgetTester tester;
  final ProviderContainer container;
  late final CronoController control;
  DateTime clock = DateTime(2026, 11, 14, 10);

  VistaCrono? get view => container.read(cronoControllerProvider);

  /// Moves the clock and the 200 ms ticks forward together.
  Future<void> advance(int seconds) async {
    for (var i = 0; i < seconds * 5; i++) {
      clock = clock.add(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
    }
  }
}

void main() {
  late FakeTimerPlatform platform;

  Future<_Harness> harness(
    WidgetTester tester, {
    FakeTimerPlatform? with_,
  }) async {
    platform = with_ ?? FakeTimerPlatform();
    final h = _Harness(tester, platform);
    addTearDown(() {
      h.control.detener();
      h.container.dispose();
    });
    return h;
  }

  testWidgets(
    'countdown: cuenta, avisa los últimos 3 segundos y suena al llegar a cero',
    (tester) async {
      final h = await harness(tester);
      const rest = Temporizador(
        id: 'd',
        nombre: 'Descanso',
        tipo: TipoTemporizador.countdown,
        trabajoSeg: 10,
      );

      expect(h.control.iniciar(rest), isTrue);
      expect(h.view!.segundos, 10);
      expect(platform.starts, 1);

      await h.advance(7);
      expect(h.view!.segundos, 3);
      expect(platform.beeps, [_tick]);

      await h.advance(2);
      expect(platform.beeps, [_tick, _tick, _tick]);
      expect(h.view, isNotNull);

      await h.advance(1);
      expect(h.view, isNull);
      expect(platform.beeps.last, _end);
      expect(platform.vibrations.last, [200, 100, 200]);
      expect(platform.stops, 1);
    },
  );

  testWidgets(
    'EMOM: una fase por minuto, con aviso en cada cambio y al terminar',
    (tester) async {
      final h = await harness(tester);
      const emom = Temporizador(
        id: 'e',
        nombre: 'EMOM',
        tipo: TipoTemporizador.emom,
        trabajoSeg: 10,
        rondas: 3,
      );

      h.control.iniciar(emom);
      expect(h.view!.crono.fase.etiqueta, 'Minuto 1');
      expect(h.view!.crono.fase.rondas, 3);

      await h.advance(10);
      expect(h.view!.crono.fase.etiqueta, 'Minuto 2');
      expect(h.view!.segundos, 10);
      expect(platform.beeps.where((b) => b == _phase), hasLength(1));

      await h.advance(10);
      expect(h.view!.crono.fase.etiqueta, 'Minuto 3');
      expect(h.view!.crono.esUltimaFase, isTrue);

      await h.advance(10);
      expect(h.view, isNull);
      expect(platform.beeps.where((b) => b == _phase), hasLength(2));
      expect(platform.beeps.last, _end);
    },
  );

  testWidgets(
    'tabata: alterna trabajo y descanso y termina sin descanso final',
    (tester) async {
      final h = await harness(tester);
      const tabata = Temporizador(
        id: 't',
        nombre: 'Tabata',
        tipo: TipoTemporizador.tabata,
        trabajoSeg: 4,
        descansoSeg: 2,
        rondas: 2,
      );

      h.control.iniciar(tabata);
      final labels = <String>[h.view!.crono.fase.etiqueta];
      for (var i = 0; i < 2; i++) {
        await h.advance(i == 0 ? 4 : 2);
        labels.add(h.view!.crono.fase.etiqueta);
      }
      expect(labels, ['Trabajo', 'Descanso', 'Trabajo']);
      expect(h.view!.crono.fase.ronda, 2);

      await h.advance(4);
      expect(
        h.view,
        isNull,
        reason: 'no hay descanso después de la última ronda',
      );
    },
  );

  testWidgets(
    'sin sonido, vibración ni pantalla encendida el temporizador sigue corriendo',
    (tester) async {
      for (final broken in [
        FakeTimerPlatform(fail: true),
        FakeTimerPlatform(failAsync: true),
      ]) {
        final h = await harness(tester, with_: broken);
        const tabata = Temporizador(
          id: 't',
          nombre: 'Tabata',
          tipo: TipoTemporizador.tabata,
          trabajoSeg: 4,
          descansoSeg: 2,
          rondas: 2,
        );

        expect(h.control.iniciar(tabata), isTrue);
        await h.advance(1);
        expect(h.view!.segundos, 3);
        await h.advance(3);
        expect(h.view!.crono.fase.etiqueta, 'Descanso');
        await h.advance(2 + 4);
        expect(h.view, isNull);
        expect(tester.takeException(), isNull);
        expect(broken.calls, contains('start'));
        expect(broken.calls, contains('beep'));
        expect(broken.calls, contains('vibrate'));
        expect(broken.calls, contains('stop'));
      }
    },
  );

  testWidgets(
    'for time sin tope cuenta hacia arriba y terminar deja el tiempo final',
    (tester) async {
      final h = await harness(tester);
      const forTime = Temporizador(
        id: 'ft',
        nombre: 'Cronómetro',
        tipo: TipoTemporizador.forTime,
      );

      expect(h.control.iniciar(forTime), isTrue);
      await h.advance(95);
      expect(h.view!.segundos, 95);
      expect(h.view!.crono.abierta, isTrue);
      expect(
        platform.beeps,
        isEmpty,
        reason: 'no hay cuenta regresiva que avisar',
      );

      final result = h.control.terminar()!;
      expect(result.seconds, 95);
      expect(result.timerId, 'ft');
      expect(result.label, 'For Time');
      expect(h.view, isNull);
      expect(platform.beeps.last, _end);
      expect(h.container.read(cronoResultsProvider).single.seconds, 95);

      // A new timer clears the last result.
      h.control.iniciar(forTime);
      expect(h.container.read(cronoResultsProvider), isEmpty);
    h.control.detener();
    },
  );

  testWidgets('for time con señal por intervalo suena cada tantos segundos', (
    tester,
  ) async {
    final h = await harness(tester);
    const forTime = Temporizador(
      id: 'ft',
      nombre: 'FT',
      tipo: TipoTemporizador.forTime,
      senalCadaSeg: 30,
    );

    h.control.iniciar(forTime);
    await h.advance(29);
    expect(platform.beeps, isEmpty);
    await h.advance(1);
    expect(platform.beeps, [_phase]);
    await h.advance(60);
    expect(platform.beeps, [_phase, _phase, _phase]);
    h.control.detener();
  });

  testWidgets(
    'Death By sigue hasta que el atleta termina y deja la ronda que alcanzó',
    (tester) async {
      final h = await harness(tester);
      const deathBy = Temporizador(
        id: 'db',
        nombre: 'Death By',
        tipo: TipoTemporizador.emom,
        trabajoSeg: 10,
        deathBy: true,
      );

      h.control.iniciar(deathBy);
      await h.advance(25);
      expect(h.view!.crono.fase.etiqueta, 'Minuto 3');

      final result = h.control.terminar()!;
      expect(result.round, 3);
      expect(result.seconds, 5);
      expect(h.view, isNull);
    },
  );

  testWidgets('pausar un for time detiene la cuenta', (tester) async {
    final h = await harness(tester);
    h.control.iniciar(
      const Temporizador(
        id: 'ft',
        nombre: 'FT',
        tipo: TipoTemporizador.forTime,
      ),
    );
    await h.advance(10);
    h.control.alternarPausa();
    await h.advance(30);
    expect(h.view!.segundos, 10);
    h.control.alternarPausa();
    await h.advance(5);
    expect(h.view!.segundos, 15);
    h.control.detener();
  });

  testWidgets(
    'un temporizador sin duración no arranca ni toca el dispositivo',
    (tester) async {
      final h = await harness(tester);
      const empty = Temporizador(
        id: 'x',
        nombre: 'x',
        tipo: TipoTemporizador.countdown,
      );
      expect(h.control.iniciar(empty), isFalse);
      expect(platform.calls, isEmpty);
    },
  );
}
