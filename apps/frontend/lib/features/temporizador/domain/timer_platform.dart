/// What the timer asks of the device. Each call may fail or be unsupported (a browser without vibration, sound
/// blocked, no wake lock): the controller swallows every error, so an implementation may simply throw.
abstract interface class TimerPlatform {
  /// Called when a timer starts, from a user gesture: unlocks sound and keeps the screen on.
  Future<void> start();

  /// Called when the timer ends or is closed: lets the screen sleep again.
  Future<void> stop();

  /// A short tone.
  Future<void> beep({required double hz, required Duration duration});

  /// Vibrates with alternating on/off milliseconds, as `navigator.vibrate` takes them.
  Future<void> vibrate(List<int> pattern);
}
