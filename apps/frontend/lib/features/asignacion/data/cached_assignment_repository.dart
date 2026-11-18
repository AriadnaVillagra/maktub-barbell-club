import 'package:maktub_core/maktub_core.dart';

import '../../../core/offline/local_copy.dart';
import '../domain/assignment_repository.dart';

/// The club's groups with the device's copy (E7.15). Assignments and their changes are planning, which needs
/// signal, so they go straight to the server.
class CachedAssignmentRepository implements AssignmentRepository {
  CachedAssignmentRepository(this._remote, this._reads);

  final AssignmentRepository _remote;
  final LocalCopyReads _reads;

  @override
  Future<List<AthleteGroup>> groups(String clubId) => _reads.read(
    copyKey(['groups', clubId]),
    () => _remote.groups(clubId),
    encode: (gs) => [for (final g in gs) g.toJson()],
    decode: (d) => [
      for (final g in d as List)
        AthleteGroup.fromJson((g as Map).cast<String, dynamic>()),
    ],
  );

  @override
  Future<List<Assignment>> assignments(String clubId, {String? groupId}) =>
      _remote.assignments(clubId, groupId: groupId);

  @override
  Future<Assignment> assign(
    String clubId, {
    required String planId,
    required List<String> athleteIds,
    required DateTime startDate,
  }) => _remote.assign(
    clubId,
    planId: planId,
    athleteIds: athleteIds,
    startDate: startDate,
  );

  @override
  Future<Assignment> setAthletes(
    String clubId,
    String assignmentId, {
    required List<String> athleteIds,
    required DateTime date,
  }) => _remote.setAthletes(
    clubId,
    assignmentId,
    athleteIds: athleteIds,
    date: date,
  );

  @override
  Future<Assignment> end(
    String clubId,
    String assignmentId, {
    DateTime? endDate,
  }) => _remote.end(clubId, assignmentId, endDate: endDate);
}
