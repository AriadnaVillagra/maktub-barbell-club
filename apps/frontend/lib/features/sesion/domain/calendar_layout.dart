/// The ways the calendar view lays out the cycle (E7.25), like a folder's views.
enum CalendarLayout {
  /// A grid with one row per week and one column per day.
  compact,

  /// Per week, a row of day cards with their blocks.
  cards,

  /// Per week, every day in full.
  detailed,
}

/// Where the device remembers the chosen [CalendarLayout].
abstract interface class CalendarLayoutStore {
  /// The saved layout; null when there is none or it cannot be read.
  Future<CalendarLayout?> load();

  Future<void> save(CalendarLayout layout);
}
