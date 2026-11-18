import 'package:maktub_core/maktub_core.dart';

/// Test fixtures written as "the group's assignment" (before E6.7): gives [assignment] the members of its group,
/// in from its start date, as the server copies them once (`copyAssignmentAthletes`). Left as is when it
/// already lists athletes or has no group.
Future<Assignment?> withGroupMembers(
  Assignment? assignment,
  Future<List<String>> Function(String groupId) groupMembers,
) async {
  if (assignment == null ||
      assignment.members.isNotEmpty ||
      assignment.groupId == null) {
    return assignment;
  }
  return assignment.copyWith(
    members: [
      for (final id in await groupMembers(assignment.groupId!))
        AssignmentMember(athleteId: id, from: assignment.startDate),
    ],
  );
}
