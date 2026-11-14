import 'package:maktub_frontend/features/temporizador/domain/timer_platform.dart';

/// Records what the timer asks of the device. [fail] makes every call throw, and [failAsync] makes it return a
/// failed future, like a browser without sound, vibration or wake lock.
class FakeTimerPlatform implements TimerPlatform {
  FakeTimerPlatform({this.fail = false, this.failAsync = false});

  final bool fail;
  final bool failAsync;
  final calls = <String>[];
  int starts = 0;
  int stops = 0;
  final beeps = <double>[];
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
    return _attempt('stop');
  }

  @override
  Future<void> beep({required double hz, required Duration duration}) {
    beeps.add(hz);
    return _attempt('beep');
  }

  @override
  Future<void> vibrate(List<int> pattern) {
    vibrations.add(pattern);
    return _attempt('vibrate');
  }
}
