/// The timers the user keeps at hand in a club: the only ones the timer button offers (Ari, 2026-11-19).
abstract interface class QuickTimersRepository {
  /// Their ids, in the order they were chosen; empty until the user chooses some.
  Future<List<String>> ids(String clubId);

  /// Replaces the whole choice and returns it as saved.
  Future<List<String>> save(String clubId, List<String> ids);
}
