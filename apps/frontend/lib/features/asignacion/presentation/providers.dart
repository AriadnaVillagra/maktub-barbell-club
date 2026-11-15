import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_core/maktub_core.dart';

import '../../../core/offline/local_copy_providers.dart';
import '../../../core/red/api_providers.dart';
import '../../access/presentation/providers.dart';
import '../../atletas/domain/athlete_repository.dart';
import '../../atletas/presentation/providers.dart'
    show athleteRepositoryProvider;
import '../data/cached_assignment_repository.dart';
import '../data/http_assignment_repository.dart';
import '../domain/assignment_repository.dart';

/// Groups and assignments straight from the server. Tests replace it to keep the device's copy in between.
final remoteAssignmentRepositoryProvider = Provider<AssignmentRepository>(
  (ref) => HttpAssignmentRepository(ref.watch(clienteApiProvider)),
);

/// Groups with the device's copy as fallback without signal (E7.15); assignments always from the server.
final assignmentRepositoryProvider = Provider<AssignmentRepository>(
  (ref) => CachedAssignmentRepository(
    ref.watch(remoteAssignmentRepositoryProvider),
    ref.watch(localCopyReadsProvider),
  ),
);

/// Today as a calendar date; tests override it.
final assignmentTodayProvider = Provider<DateTime>(
  (ref) => soloFecha(DateTime.now()),
);

/// Who an assignment is for, as the assignments screen offers them: a group or one athlete (E8.8).
class AssignmentOwner {
  AssignmentOwner.group(AthleteGroup group)
    : groupId = group.id,
      athleteId = null,
      name = group.name;

  const AssignmentOwner.athlete(String this.athleteId, this.name)
    : groupId = null;

  final String? groupId;
  final String? athleteId;
  final String name;

  bool get isGroup => groupId != null;

  /// "Grupo Barra" or the athlete's name.
  String get label => isGroup ? 'Grupo $name' : name;

  /// Stable across reloads: the kind of owner and its id.
  String get key => isGroup ? 'grupo-$groupId' : 'atleta-$athleteId';

  bool owns(Assignment a) =>
      isGroup ? a.groupId == groupId : a.athleteId == athleteId;
}

/// What the assignments screen shows: who a plan can be assigned to (the club's groups, then its athletes) and every
/// assignment of the club, newest first. An athlete's own plan lives alongside their group's (E8.8).
class ClubAssignments {
  const ClubAssignments({required this.owners, required this.assignments});

  final List<AssignmentOwner> owners;
  final List<Assignment> assignments;

  bool get hasGroup => owners.any((o) => o.isGroup);

  /// The assignments of [owner], newest first.
  List<Assignment> of(AssignmentOwner owner) => [
    for (final a in assignments)
      if (owner.owns(a)) a,
  ];

  /// The active assignment of [owner]; null when it has none (D14: at most one).
  Assignment? activeOf(AssignmentOwner owner) {
    for (final a in of(owner)) {
      if (a.status == AssignmentStatus.active) return a;
    }
    return null;
  }

  /// The owners a new plan can go to: those without an active assignment.
  List<AssignmentOwner> get free => [
    for (final o in owners)
      if (activeOf(o) == null) o,
  ];
}

Future<ClubAssignments> _loadClubAssignments(
  String? clubId,
  AssignmentRepository repo,
  AthleteRepository athletes,
) async {
  if (clubId == null) {
    return const ClubAssignments(owners: [], assignments: []);
  }
  final groups = await repo.groups(clubId);
  final people = await athletes.athletes(clubId);
  return ClubAssignments(
    owners: [
      for (final g in groups) AssignmentOwner.group(g),
      for (final a in people) AssignmentOwner.athlete(a.id, a.name),
    ],
    assignments: await repo.assignments(clubId),
  );
}

final clubAssignmentsProvider = FutureProvider.autoDispose<ClubAssignments>((
  ref,
) async {
  final clubId = (await ref.watch(meProvider.future))?.activeClub?.club.id;
  return _loadClubAssignments(
    clubId,
    ref.watch(assignmentRepositoryProvider),
    ref.watch(athleteRepositoryProvider),
  );
});

/// The owners and assignments right now, for an action outside the assignments screen.
Future<ClubAssignments> fetchClubAssignments(WidgetRef ref) async {
  final clubId = (await ref.read(meProvider.future))?.activeClub?.club.id;
  return _loadClubAssignments(
    clubId,
    ref.read(assignmentRepositoryProvider),
    ref.read(athleteRepositoryProvider),
  );
}

/// Assigns [planId] to [owner] in the active club and refreshes the screen. Errors propagate.
Future<void> assignPlan(
  WidgetRef ref, {
  required String planId,
  required AssignmentOwner owner,
  required DateTime startDate,
}) async {
  final clubId = (await ref.read(meProvider.future))?.activeClub?.club.id;
  if (clubId == null) return;
  await ref
      .read(assignmentRepositoryProvider)
      .assign(
        clubId,
        planId: planId,
        groupId: owner.groupId,
        athleteId: owner.athleteId,
        startDate: startDate,
      );
  ref.invalidate(clubAssignmentsProvider);
}

/// Ends [assignmentId] in the active club and refreshes the screen. Errors propagate.
Future<void> endAssignment(WidgetRef ref, String assignmentId) async {
  final clubId = (await ref.read(meProvider.future))?.activeClub?.club.id;
  if (clubId == null) return;
  await ref.read(assignmentRepositoryProvider).end(clubId, assignmentId);
  ref.invalidate(clubAssignmentsProvider);
}
