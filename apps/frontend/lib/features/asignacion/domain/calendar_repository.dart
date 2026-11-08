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

abstract interface class CalendarRepository {
  /// Where [date] falls in the active assignment of [groupId], or null when the group has none.
  Future<CalendarLocation?> locate(
    String clubId,
    String groupId,
    DateTime date,
  );

  /// The published version of [planId]. Throws `ErrorDeApi` (404) when the plan has none.
  Future<PublishedPlanView> publishedPlan(String clubId, String planId);
}
