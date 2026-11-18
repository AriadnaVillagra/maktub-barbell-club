import 'package:maktub_frontend/features/temporizador/domain/timer_platform.dart';

/// Records what the timer asks of the device. [fail] makes every call throw, and [failAsync] makes it return a
/// failed future, like a browser without sound, vibration or wake lock.
class FakeTimerPlatform implements TimerPlatform {
  FakeTimerPlatform({this.fail = false, this.failAsync = false, DateTime Function()? clock})
    : clock = clock ?? DateTime.now;

  /// The device's clock, to tell which scheduled tones already played.
  DateTime Function() clock;

  final bool fail;
  final bool failAsync;
  final calls = <String>[];
  int starts = 0;
  int stops = 0;
  /// Tones played at once.
  final beeps = <double>[];

  /// The tones scheduled last, still to play or already played.
  List<ScheduledTone> scheduled = const [];
  final _playedScheduled = <ScheduledTone>[];
  int schedules = 0;

  /// What was heard up to now, in order: tones played at once and scheduled ones whose time came before they were
  /// replaced or cancelled.
  List<double> get heard {
    final now = clock();
    final all = [
      ..._playedScheduled.map((t) => (at: t.at, hz: t.hz)),
      ...scheduled.where((t) => !t.at.isAfter(now)).map((t) => (at: t.at, hz: t.hz)),
      ..._immediate,
    ]..sort((a, b) => a.at.compareTo(b.at));
    return [for (final t in all) t.hz];
  }

  final _immediate = <({DateTime at, double hz})>[];
  final vibrations = <List<int>>[];

  Future<void> _attempt(String call) {
    calls.add(call);
    if (fail) throw UnsupportedError(call);
    if (failAsync) return Future.error(UnsupportedError(call));
    return Future.value();
  }

  @override
  Future<void> start() {
    starts++;
    return _attempt('start');
  }

  @override
  Future<void> stop() {
    stops++;
    final now = clock();
    _playedScheduled.addAll(scheduled.where((t) => !t.at.isAfter(now)));
    scheduled = const [];
    return _attempt('stop');
  }

  @override
  Future<void> beep({required double hz, required Duration duration}) {
    beeps.add(hz);
    _immediate.add((at: clock(), hz: hz));
    return _attempt('beep');
  }

  @override
  Future<void> schedule(List<ScheduledTone> tones) {
    final now = clock();
    _playedScheduled.addAll(scheduled.where((t) => !t.at.isAfter(now)));
    scheduled = tones;
    schedules++;
    return _attempt('schedule');
  }

  @override
  Future<void> vibrate(List<int> pattern) {
    vibrations.add(pattern);
    return _attempt('vibrate');
  }
}
