import 'package:maktub_core/maktub_core.dart';

/// Where a date falls in the group's active assignment (`.../grupos/{id}/ubicacion`).
class CalendarLocation {
  const CalendarLocation({
    required this.assignmentId,
    required this.planId,
    required this.startDate,
    required this.cycle,
    required this.week,
  });

  final String assignmentId;
  final String planId;
  final DateTime startDate;

  /// 1-based cycle number.
  final int cycle;

  /// 1 to 4.
  final int week;
}

/// The published version of a plan, the only one athletes see. Never the draft.
class PublishedPlanView {
  const PublishedPlanView({
    required this.id,
    required this.name,
    required this.type,
    required this.weekModels,
    required this.weekAssignment,
    required this.publishedAt,
  });

  final String id;
  final String name;
  final PlanType type;
  final List<WeekModel> weekModels;

  /// The week model id of each of the four weeks.
  final List<String> weekAssignment;
  final DateTime publishedAt;

  /// The week model of the 1-based [week], or null when the assignment has none for it.
  WeekModel? weekModelOf(int week) {
    if (week < 1 || week > weekAssignment.length) return null;
    for (final m in weekModels) {
      if (m.id == weekAssignment[week - 1]) return m;
    }
    return null;
  }
}

/// Whether one day of the plan, in a cycle and week, has sets recorded in the group's session (E7.13).
/// There is no third state here: recovered and missed belong to the coach (3.6).
class DayState {
  const DayState({
    required this.cycle,
    required this.week,
    required this.day,
    required this.done,
  });

  final int cycle;
  final int week;

  /// 1-based.
  final int day;

  /// Done (sets recorded) or pending.
  final bool done;
}

/// The day the calendar opens on (D13): the first of [week] in [cycle], among [dayCount] days, without sets
/// recorded; day 1 when all are done or [states] knows nothing (no sessions yet).
int firstPendingDay(
  Iterable<DayState> states, {
  required int cycle,
  required int week,
  required int dayCount,
}) {
  final done = {
    for (final s in states)
      if (s.done && s.cycle == cycle && s.week == week) s.day,
  };
  for (var d = 1; d <= dayCount; d++) {
    if (!done.contains(d)) return d;
  }
  return 1;
}

abstract interface class CalendarRepository {
  /// Where [date] falls in the active assignment of [groupId], or null when the group has none.
  Future<CalendarLocation?> locate(
    String clubId,
    String groupId,
    DateTime date,
  );

  /// The published version of [planId]. Throws `ErrorDeApi` (404) when the plan has none.
  Future<PublishedPlanView> publishedPlan(String clubId, String planId);

  /// The state of every day of the active assignment of [groupId] in the cycles and weeks that
  /// [from]..[to] touch. Empty when the group has no active assignment.
  Future<List<DayState>> dayStates(
    String clubId,
    String groupId,
    DateTime from,
    DateTime to,
  );
}
