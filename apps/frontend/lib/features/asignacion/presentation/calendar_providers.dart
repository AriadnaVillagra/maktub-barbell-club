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
  });

  /// No active assignment (or no group).
  const CalendarData.empty()
    : location = null,
      plan = null,
      exerciseNames = const {};

  final CalendarLocation? location;
  final PublishedPlanView? plan;

  /// Exercise name by id.
  final Map<String, String> exerciseNames;

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
  return CalendarData(
    location: location,
    plan: plan,
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
/// the backend gave for today, day 1 (D13, until sessions exist; the first pending day arrives with E7.13).
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
