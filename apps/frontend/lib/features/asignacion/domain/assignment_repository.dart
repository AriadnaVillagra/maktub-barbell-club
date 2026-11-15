import 'package:maktub_core/maktub_core.dart';

abstract interface class AssignmentRepository {
  /// The club's groups. Coach only.
  Future<List<AthleteGroup>> groups(String clubId);

  /// The club's assignments, newest first; only [groupId]'s when given.
  Future<List<Assignment>> assignments(String clubId, {String? groupId});

  /// Assigns the published version of [planId] from [startDate] to [groupId] or to the one athlete [athleteId]
  /// (E8.8), exactly one of the two. Throws `ErrorDeApi` with the backend's message when it refuses (no published
  /// version, the group or athlete already has an active one...).
  Future<Assignment> assign(
    String clubId, {
    required String planId,
    String? groupId,
    String? athleteId,
    required DateTime startDate,
  });

  /// Ends an assignment (today unless [endDate] is given).
  Future<Assignment> end(
    String clubId,
    String assignmentId, {
    DateTime? endDate,
  });
}
