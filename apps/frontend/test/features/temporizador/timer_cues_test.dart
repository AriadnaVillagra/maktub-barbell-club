import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/temporizador/domain/crono.dart';
import 'package:maktub_frontend/features/temporizador/domain/timer_cues.dart';

void main() {
  final t0 = DateTime(2026, 11, 18, 10);
  List<(int, TimerCue)> secondsOf(List<ScheduledCue> cues) => [
    for (final c in cues) (c.at.difference(t0).inSeconds, c.cue),
  ];

  test('a countdown: the last 3 seconds and the end', () {
    final crono = Crono.iniciar(
      const Temporizador(id: 'd', nombre: 'D', tipo: TipoTemporizador.countdown, trabajoSeg: 10),
      t0,
    )!;
    expect(secondsOf(cuesAhead(crono, t0)), [
      (7, TimerCue.tick),
      (8, TimerCue.tick),
      (9, TimerCue.tick),
      (10, TimerCue.end),
    ]);
    // Only what is still ahead.
    expect(secondsOf(cuesAhead(crono, t0.add(const Duration(seconds: 8)))), [
      (9, TimerCue.tick),
      (10, TimerCue.end),
    ]);
  });

  test('an open for time: its signals up to the horizon, and no end', () {
    final crono = Crono.iniciar(
      const Temporizador(id: 'f', nombre: 'F', tipo: TipoTemporizador.forTime, senalCadaSeg: 60),
      t0,
    )!;
    final cues = cuesAhead(crono, t0, horizon: const Duration(minutes: 5));
    expect(secondsOf(cues), [for (var m = 1; m <= 5; m++) (m * 60, TimerCue.phase)]);
  });

  test('a paused timer gives none', () {
    final crono = Crono.iniciar(
      const Temporizador(id: 'd', nombre: 'D', tipo: TipoTemporizador.countdown, trabajoSeg: 10),
      t0,
    )!.alternarPausa(t0.add(const Duration(seconds: 2)));
    expect(cuesAhead(crono, t0.add(const Duration(seconds: 2))), isEmpty);
  });

  test('a Death By stops at the horizon', () {
    final crono = Crono.iniciar(
      const Temporizador(id: 'db', nombre: 'DB', tipo: TipoTemporizador.emom, trabajoSeg: 60, deathBy: true),
      t0,
    )!;
    final cues = cuesAhead(crono, t0, horizon: const Duration(minutes: 3));
    expect(cues.last.at.difference(t0), const Duration(minutes: 3));
    expect(cues.where((c) => c.cue == TimerCue.phase), hasLength(3));
  });
}
