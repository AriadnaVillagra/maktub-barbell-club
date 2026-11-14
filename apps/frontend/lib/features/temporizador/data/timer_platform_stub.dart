import 'package:flutter/services.dart';

import '../domain/timer_platform.dart';

/// Outside the web: haptics and the system sound, and nothing for the screen.
TimerPlatform createTimerPlatform() => _DeviceTimerPlatform();

class _DeviceTimerPlatform implements TimerPlatform {
  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> beep({required double hz, required Duration duration}) => SystemSound.play(SystemSoundType.alert);

  @override
  Future<void> vibrate(List<int> pattern) => HapticFeedback.heavyImpact();
}
