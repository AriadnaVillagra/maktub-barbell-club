import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/red/api_providers.dart';
import '../../access/presentation/providers.dart';
import '../../atletas/presentation/providers.dart' show todayProvider;
import '../../catalogo/presentation/providers.dart'
    show catalogRepositoryProvider;
import '../data/http_calendar_repository.dart';
import '../domain/calendar_repository.dart';
import 'providers.dart' show assignmentRepositoryProvider;

final calendarRepositoryProvider = Provider<CalendarRepository>(
  (ref) => HttpCalendarRepository(ref.watch(clienteApiProvider)),
);

/// What the calendar screen shows for today: where today falls and the published plan, or null when the
/// group has no active assignment.
class CalendarData {
  const CalendarData({
    required this.location,
    required this.plan,
    required this.exerciseNames,
    this.dayStates = const [],
  });

  /// No active assignment (or no group).
  const CalendarData.empty()
    : location = null,
      plan = null,
      exerciseNames = const {},
      dayStates = const [];

  final CalendarLocation? location;
  final PublishedPlanView? plan;

  /// Exercise name by id.
  final Map<String, String> exerciseNames;

  /// Done or pending state of the days of the current cycle (E7.13).
  final List<DayState> dayStates;

  /// Whether the day is done; false when nothing says so.
  bool isDone(int week, int day) => dayStates.any(
    (s) =>
        s.cycle == location!.cycle && s.week == week && s.day == day && s.done,
  );

  bool get hasPlan => location != null && plan != null;
}

final calendarProvider = FutureProvider.autoDispose<CalendarData>((ref) async {
  final clubId = (await ref.watch(meProvider.future))?.activeClub?.club.id;
  if (clubId == null) return const CalendarData.empty();
  final groups = await ref.watch(assignmentRepositoryProvider).groups(clubId);
  if (groups.isEmpty) return const CalendarData.empty();
  final calendar = ref.watch(calendarRepositoryProvider);
  final location = await calendar.locate(
    clubId,
    groups.first.id,
    ref.watch(todayProvider),
  );
  if (location == null) return const CalendarData.empty();
  final plan = await calendar.publishedPlan(clubId, location.planId);
  final exercises = await ref
      .watch(catalogRepositoryProvider)
      .exercises(clubId);
  // The four weeks of the current cycle, which is what the screen lets the user pick from.
  final cycleStart = DateTime.utc(
    location.startDate.year,
    location.startDate.month,
    location.startDate.day,
  ).add(Duration(days: (location.cycle - 1) * 28));
  final dayStates = await calendar.dayStates(
    clubId,
    groups.first.id,
    cycleStart,
    cycleStart.add(const Duration(days: 27)),
  );
  return CalendarData(
    location: location,
    plan: plan,
    dayStates: dayStates,
    exerciseNames: {for (final e in exercises) e.id: e.name},
  );
});

/// The week and day the user picked.
class CalendarSelection {
  const CalendarSelection(this.week, this.day);

  final int week;
  final int day;
}

/// The user's choice of week and day. Null state means "nothing chosen": the screen then opens on the week
/// the backend gave for today, on its first day without sets recorded (D13; day 1 when all are done).
class CalendarSelectionNotifier extends Notifier<CalendarSelection?> {
  @override
  CalendarSelection? build() => null;

  /// Choosing a week goes to its first day, as the reference does.
  void selectWeek(int week) => state = CalendarSelection(week, 1);

  void selectDay(int week, int day) => state = CalendarSelection(week, day);
}

final calendarSelectionProvider =
    NotifierProvider.autoDispose<CalendarSelectionNotifier, CalendarSelection?>(
      CalendarSelectionNotifier.new,
    );
