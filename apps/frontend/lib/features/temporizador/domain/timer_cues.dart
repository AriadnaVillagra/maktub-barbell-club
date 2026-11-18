import 'crono.dart';

/// The kinds of warning a running timer gives: the last 3 seconds of a phase, a phase change (or an interval signal
/// of a for time), and the end.
enum TimerCue { tick, phase, end }

/// A warning at a wall-clock instant.
typedef ScheduledCue = ({DateTime at, TimerCue cue});

/// Every warning [crono] will give from [now] on if nobody touches it, in order: the current phase and the ones after
/// it, each starting when the one before ends. They are known in advance so the device can play them on its own clock
/// while the app is in the background, when its own ticks stop. An open phase (for time without a cap) has no end:
/// only its interval signals are listed, up to [horizon], and nothing after it. A paused timer gives none.
List<ScheduledCue> cuesAhead(
  Crono crono,
  DateTime now, {
  Duration horizon = const Duration(hours: 1),
}) {
  if (crono.enPausa) return const [];
  final limit = now.add(horizon);
  final cues = <ScheduledCue>[];
  void add(DateTime at, TimerCue cue) {
    if (at.isAfter(now) && !at.isAfter(limit)) cues.add((at: at, cue: cue));
  }

  DateTime? previousEnd;
  for (var i = crono.indice; i < crono.fases.length; i++) {
    final fase = crono.fases[i];
    final seconds = Duration(seconds: fase.segundos);
    // An open phase keeps its start in `fin`; a closed one, its end.
    final start = previousEnd ?? (fase.abierta ? crono.fin : crono.fin.subtract(seconds));
    final end = fase.abierta ? null : start.add(seconds);

    if (fase.senalCadaSeg case final every? when every > 0) {
      for (var at = start.add(Duration(seconds: every));
          (end == null || at.isBefore(end)) && !at.isAfter(limit);
          at = at.add(Duration(seconds: every))) {
        add(at, TimerCue.phase);
      }
    }
    if (end == null) break;

    for (var s = 3; s >= 1; s--) {
      final at = end.subtract(Duration(seconds: s));
      if (at.isAfter(start)) add(at, TimerCue.tick);
    }
    add(end, i == crono.fases.length - 1 ? TimerCue.end : TimerCue.phase);
    if (end.isAfter(limit)) break;
    previousEnd = end;
  }
  return cues;
}
