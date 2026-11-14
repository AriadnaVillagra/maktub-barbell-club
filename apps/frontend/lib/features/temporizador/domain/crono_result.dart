/// What a work phase took when the athlete finished it: the final time of a for time, or the round a Death By reached.
/// The timer only keeps it; saving it with the WoD is up to the screen that owns the WoD (E7.12, F11).
class CronoResult {
  const CronoResult({
    required this.timerId,
    required this.timerName,
    required this.label,
    required this.set,
    required this.round,
    required this.seconds,
    required this.at,
  });

  final String timerId;
  final String timerName;

  /// The phase's label, such as "For Time" or "Minuto 7".
  final String label;

  /// The 1-based set and round of the phase.
  final int set;
  final int round;

  /// Seconds the phase had run when it was finished (paused time does not count).
  final int seconds;

  /// When it was finished.
  final DateTime at;
}
