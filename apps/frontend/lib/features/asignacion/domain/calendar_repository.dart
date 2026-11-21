import 'package:maktub_core/maktub_core.dart';

/// Where a date falls in an active assignment: the group's (`.../grupos/{id}/ubicacion`) or one of those an athlete
/// trains (`.../atletas/{id}/ubicacion`, E8.8).
class CalendarLocation {
  const CalendarLocation({
    required this.assignmentId,
    required this.planId,
    required this.startDate,
    required this.cycle,
    required this.week,
    this.groupId,
    this.athleteId,
    this.athleteIds,
  });

  final String assignmentId;
  final String planId;
  final DateTime startDate;

  /// The group the assignment is for; null for an athlete's own plan, or when the answer did not say.
  final String? groupId;

  /// The one athlete the assignment is for, when it is their own plan (E8.8). Only in answers from before E6.7.
  final String? athleteId;

  /// The athletes in the assignment on the date asked about (E6.7); null in answers and copies from before it.
  final List<String>? athleteIds;

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

/// How far one athlete got through one day of the plan, in a cycle and week (E7.13; per athlete and with its real
/// progress since Ari's decision of 2026-11-21, which replaces D13's marking). Read without an athlete, it is the old
/// marking: done when anyone recorded a set, without counts. Recovered and missed belong to the coach (3.6).
class DayState {
  const DayState({
    required this.cycle,
    required this.week,
    required this.day,
    required this.status,
    this.doneSets,
    this.totalSets,
    this.date,
  });

  final int cycle;
  final int week;

  /// 1-based.
  final int day;

  final DayProgressStatus status;

  /// Planned sets the athlete has done, and the day's planned sets; null when read without an athlete.
  final int? doneSets;
  final int? totalSets;

  /// Every planned set done.
  bool get done => status == DayProgressStatus.done;

  /// The date of the session where the day was started (the first one, if it was done on several dates); null while
  /// pending. A session belongs to a date, so a day started on another date is looked up with this one.
  final DateTime? date;
}

/// The date of the session where [day] of [week] in [cycle] was started (some set done), or null when [states] do
/// not have it.
DateTime? doneDateOf(
  Iterable<DayState> states, {
  required int cycle,
  required int week,
  required int day,
}) => states
    .where((s) => s.date != null && s.cycle == cycle && s.week == week && s.day == day)
    .firstOrNull
    ?.date;


/// The day the calendar opens on (D13): the first of [week] in [cycle], among [dayCount] days, not fully done; day
/// 1 when all are done or [states] knows nothing (no sessions yet).
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

  /// Where [date] falls in every active assignment [athleteId] trains: their groups' and their own (E8.8), the
  /// groups' first. Empty when there is none.
  Future<List<CalendarLocation>> locateAthlete(
    String clubId,
    String athleteId,
    DateTime date,
  );

  /// The published version of [planId]. Throws `ErrorDeApi` (404) when the plan has none.
  Future<PublishedPlanView> publishedPlan(String clubId, String planId);

  /// The state of every day of the assignment [assignmentId], a group's or an athlete's, in the cycles and weeks
  /// that [from]..[to] touch: [athleteId]'s progress, or without one, done when anyone recorded a set.
  Future<List<DayState>> dayStates(
    String clubId,
    String assignmentId,
    DateTime from,
    DateTime to, {
    String? athleteId,
  });
}
