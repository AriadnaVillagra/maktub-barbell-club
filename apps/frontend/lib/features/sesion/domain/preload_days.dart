import 'package:maktub_core/maktub_core.dart';

import '../../access/domain/me_repository.dart';
import '../../asignacion/domain/assignment_repository.dart';
import '../../asignacion/domain/calendar_repository.dart';
import '../../atletas/domain/athlete_repository.dart';
import '../../catalogo/domain/catalog_admin_repository.dart';
import '../../catalogo/domain/catalog_repository.dart';
import 'proposed_days.dart';

/// How many days after today the preload covers (E7.15): today and the next seven.
const preloadDaysAhead = 7;

/// The first and last date of [cycle] of an assignment started on [startDate] (cycles of 28 days).
(DateTime, DateTime) cycleDates(DateTime startDate, int cycle) {
  final start = DateTime.utc(
    startDate.year,
    startDate.month,
    startDate.day,
  ).add(Duration(days: (cycle - 1) * 28));
  return (start, start.add(const Duration(days: 27)));
}

/// Downloads what the day's screens read, for today and the next [preloadDaysAhead] days, through repositories that
/// keep a copy on the device (E7.15): who the user is and the active club, the group, where each date falls in each of the user's plans, the
/// plans, the days' states of each cycle, the catalog, the timers, the equipment, the athletes and every athlete's
/// proposed kilos. The reads are the same the screens do, so the copy serves them as they are.
///
/// Best effort: a read that fails does not stop the others. Without signal the reads answer from the copy, which
/// changes nothing.
///
/// One read at a time: the server asks the database one query at a time, so reads sent together queue there, and
/// the screen's own reads waited behind them (the session of the day took ~5 s to open, 2026-11-19). This runs in
/// the background; taking longer costs nothing.
class PreloadDays {
  PreloadDays({
    required this.me,
    required this.assignments,
    required this.calendar,
    required this.catalog,
    required this.catalogAdmin,
    required this.athletes,
    required this.proposedDays,
  });

  final MeRepository me;
  final AssignmentRepository assignments;
  final CalendarRepository calendar;
  final CatalogRepository catalog;
  final CatalogAdminRepository catalogAdmin;
  final AthleteRepository athletes;
  final ProposedDaysRepository proposedDays;

  Future<void> call(DateTime today) async {
    final access = (await _try(me.fetch))?.activeClub;
    if (access == null) return;
    final clubId = access.club.id;
    final groups = await _try(() => assignments.groups(clubId));
    final athleteId = access.athleteId;
    if (athleteId != null || (groups != null && groups.isNotEmpty)) {
      await _preloadDays(
          clubId,
          soloFecha(today),
          athleteId,
          // The same read the session screen does: the athlete's plans (their groups' and their own, E8.8), or the
          // first group's for a user who is not an athlete.
          (d) async => athleteId != null
              ? await calendar.locateAthlete(clubId, athleteId, d)
              : [?await calendar.locate(clubId, groups!.first.id, d)],
      );
    }
    await _try(() => catalog.exercises(clubId));
    await _try(() => catalogAdmin.timers(clubId));
    await _try(() => catalogAdmin.team(clubId));
    if (access.can(Accion.verReportesDeTodos)) await _try(() => athletes.athletes(clubId));
  }

  Future<void> _preloadDays(
    String clubId,
    DateTime today,
    String? athleteId,
    Future<List<CalendarLocation>> Function(DateTime date) locate,
  ) async {
    final dates = [
      for (var i = 0; i <= preloadDaysAhead; i++) today.add(Duration(days: i)),
    ];
    final located = [for (final d in dates) await _try(() => locate(d))];
    final plans = <String>{};
    final cycles = <(String, DateTime, int, String?)>{};
    final byAssignment = <String, List<DateTime>>{};
    for (var i = 0; i < dates.length; i++) {
      for (final l in located[i] ?? const <CalendarLocation>[]) {
        plans.add(l.planId);
        // The days' states of the tab the session screen opens on: the user's, else the plan's first athlete.
        final members = l.athleteIds;
        cycles.add((
          l.assignmentId,
          l.startDate,
          l.cycle,
          members == null || members.contains(athleteId) ? athleteId : members.firstOrNull,
        ));
        (byAssignment[l.assignmentId] ??= []).add(dates[i]);
      }
    }
    for (final p in plans) {
      await _try(() => calendar.publishedPlan(clubId, p));
    }
    for (final (assignmentId, start, cycle, athlete) in cycles) {
      final (from, to) = cycleDates(start, cycle);
      await _try(
        () => calendar.dayStates(clubId, assignmentId, from, to, athleteId: athlete),
      );
    }
    for (final e in byAssignment.entries) {
      await _try(() => proposedDays.proposedDays(clubId, e.key, e.value.first, e.value.last));
    }
  }

  static Future<T?> _try<T>(Future<T> Function() read) async {
    try {
      return await read();
    } catch (_) {
      return null;
    }
  }
}
