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
    final pending = <Future<void>>[
      _try(() => catalog.exercises(clubId)),
      _try(() => catalogAdmin.timers(clubId)),
      _try(() => catalogAdmin.team(clubId)),
      if (access.can(Accion.verReportesDeTodos))
        _try(() => athletes.athletes(clubId)),
    ];
    final groups = await _try(() => assignments.groups(clubId));
    final athleteId = access.athleteId;
    if (athleteId != null || (groups != null && groups.isNotEmpty)) {
      pending.add(
        _preloadDays(
          clubId,
          soloFecha(today),
          // The same read the session screen does: the athlete's plans (their groups' and their own, E8.8), or the
          // first group's for a user who is not an athlete.
          (d) async => athleteId != null
              ? await calendar.locateAthlete(clubId, athleteId, d)
              : [?await calendar.locate(clubId, groups!.first.id, d)],
        ),
      );
    }
    await Future.wait(pending);
  }

  Future<void> _preloadDays(
    String clubId,
    DateTime today,
    Future<List<CalendarLocation>> Function(DateTime date) locate,
  ) async {
    final dates = [
      for (var i = 0; i <= preloadDaysAhead; i++) today.add(Duration(days: i)),
    ];
    final located = await Future.wait([
      for (final d in dates) _try(() => locate(d)),
    ]);
    final plans = <String>{};
    final cycles = <(String, DateTime, int)>{};
    final byAssignment = <String, List<DateTime>>{};
    for (var i = 0; i < dates.length; i++) {
      for (final l in located[i] ?? const <CalendarLocation>[]) {
        plans.add(l.planId);
        cycles.add((l.assignmentId, l.startDate, l.cycle));
        (byAssignment[l.assignmentId] ??= []).add(dates[i]);
      }
    }
    await Future.wait([
      for (final p in plans) _try(() => calendar.publishedPlan(clubId, p)),
      for (final (assignmentId, start, cycle) in cycles)
        _try(() {
          final (from, to) = cycleDates(start, cycle);
          return calendar.dayStates(clubId, assignmentId, from, to);
        }),
      for (final e in byAssignment.entries)
        _try(
          () => proposedDays.proposedDays(
            clubId,
            e.key,
            e.value.first,
            e.value.last,
          ),
        ),
    ]);
  }

  static Future<T?> _try<T>(Future<T> Function() read) async {
    try {
      return await read();
    } catch (_) {
      return null;
    }
  }
}
