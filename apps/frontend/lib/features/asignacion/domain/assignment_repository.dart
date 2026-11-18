import 'package:maktub_core/maktub_core.dart';

abstract interface class AssignmentRepository {
  /// The club's groups. Coach only.
  Future<List<AthleteGroup>> groups(String clubId);

  /// The club's assignments, newest first; only [groupId]'s when given.
  Future<List<Assignment>> assignments(String clubId, {String? groupId});

  /// Assigns the published version of [planId] from [startDate] to [athleteIds] (E6.7). Throws `ErrorDeApi` with
  /// the backend's message when it refuses (no published version, an athlete not in the club...).
  Future<Assignment> assign(
    String clubId, {
    required String planId,
    required List<String> athleteIds,
    required DateTime startDate,
  });

  /// Sets who does [assignmentId] from [date] on to [athleteIds] (E6.7): those removed keep the days until the day
  /// before, those added are in from [date]. The plan goes on. Throws `ErrorDeApi` when the backend refuses.
  Future<Assignment> setAthletes(
    String clubId,
    String assignmentId, {
    required List<String> athleteIds,
    required DateTime date,
  });

  /// Ends an assignment (today unless [endDate] is given).
  Future<Assignment> end(
    String clubId,
    String assignmentId, {
    DateTime? endDate,
  });
}
