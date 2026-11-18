/// A tone to play at a wall-clock instant.
typedef ScheduledTone = ({DateTime at, double hz, Duration duration});

/// What the timer asks of the device. Each call may fail or be unsupported (a browser without vibration, sound
/// blocked, no wake lock): the controller swallows every error, so an implementation may simply throw.
abstract interface class TimerPlatform {
  /// Called when a timer starts, from a user gesture: unlocks sound and keeps the screen on.
  Future<void> start();

  /// Called when the timer ends or is closed: lets the screen sleep again.
  Future<void> stop();

  /// A short tone, now.
  Future<void> beep({required double hz, required Duration duration});

  /// Plays these tones at their instants on the device's own clock, so they sound while the app is in the
  /// background. Replaces whatever was scheduled before; an empty list cancels it.
  Future<void> schedule(List<ScheduledTone> tones);

  /// Vibrates with alternating on/off milliseconds, as `navigator.vibrate` takes them.
  Future<void> vibrate(List<int> pattern);
}
