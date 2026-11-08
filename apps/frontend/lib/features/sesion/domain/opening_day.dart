/// Which day the session screen opens on (D13): the first day of the week without recorded sets, or day 1 if
/// all of them have some (or the week has none). Pure; [daysWithRecords] are the 1-based days of the group's
/// session in that week that have recorded sets.
int firstPendingDay(int dayCount, Set<int> daysWithRecords) {
  for (var day = 1; day <= dayCount; day++) {
    if (!daysWithRecords.contains(day)) return day;
  }
  return 1;
}
