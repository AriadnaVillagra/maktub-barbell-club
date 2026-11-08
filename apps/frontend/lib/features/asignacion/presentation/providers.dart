import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/api_providers.dart';
import '../../access/presentation/providers.dart';
import '../data/http_assignment_repository.dart';
import '../domain/assignment_repository.dart';

final assignmentRepositoryProvider = Provider<AssignmentRepository>(
  (ref) => HttpAssignmentRepository(ref.watch(clienteApiProvider)),
);

/// Today as a calendar date; tests override it.
final assignmentTodayProvider = Provider<DateTime>(
  (ref) => soloFecha(DateTime.now()),
);

/// What the assignments screen shows: the club's group (M1 has one) and its assignments, newest first.
class GroupAssignments {
  const GroupAssignments({required this.group, required this.assignments});

  final AthleteGroup? group;
  final List<Assignment> assignments;

  Assignment? get active {
    for (final a in assignments) {
      if (a.status == AssignmentStatus.active) return a;
    }
    return null;
  }
}

Future<GroupAssignments> _loadGroupAssignments(
  String? clubId,
  AssignmentRepository repo,
) async {
  if (clubId == null) {
    return const GroupAssignments(group: null, assignments: []);
  }
  final groups = await repo.groups(clubId);
  if (groups.isEmpty) {
    return const GroupAssignments(group: null, assignments: []);
  }
  final group = groups.first;
  return GroupAssignments(
    group: group,
    assignments: await repo.assignments(clubId, groupId: group.id),
  );
}

final groupAssignmentsProvider = FutureProvider.autoDispose<GroupAssignments>((
  ref,
) async {
  final clubId = (await ref.watch(meProvider.future))?.activeClub?.club.id;
  return _loadGroupAssignments(clubId, ref.watch(assignmentRepositoryProvider));
});

/// The group and its assignments right now, for an action outside the assignments screen.
Future<GroupAssignments> fetchGroupAssignments(WidgetRef ref) async {
  final clubId = (await ref.read(meProvider.future))?.activeClub?.club.id;
  return _loadGroupAssignments(clubId, ref.read(assignmentRepositoryProvider));
}

/// Assigns [planId] to [groupId] in the active club and refreshes the screen. Errors propagate.
Future<void> assignPlan(
  WidgetRef ref, {
  required String planId,
  required String groupId,
  required DateTime startDate,
}) async {
  final clubId = (await ref.read(meProvider.future))?.activeClub?.club.id;
  if (clubId == null) return;
  await ref
      .read(assignmentRepositoryProvider)
      .assign(clubId, planId: planId, groupId: groupId, startDate: startDate);
  ref.invalidate(groupAssignmentsProvider);
}

/// Ends [assignmentId] in the active club and refreshes the screen. Errors propagate.
Future<void> endAssignment(WidgetRef ref, String assignmentId) async {
  final clubId = (await ref.read(meProvider.future))?.activeClub?.club.id;
  if (clubId == null) return;
  await ref.read(assignmentRepositoryProvider).end(clubId, assignmentId);
  ref.invalidate(groupAssignmentsProvider);
}
