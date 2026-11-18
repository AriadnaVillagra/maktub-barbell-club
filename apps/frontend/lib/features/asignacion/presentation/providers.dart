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

/// An athlete of the club, as the assignment screens offer them.
typedef ClubAthlete = ({String id, String name});

/// What the assignments screen shows: the club's athletes (who a plan can be for) and every assignment of the club,
/// newest first. An athlete can be in any number of active assignments (E6.7).
class ClubAssignments {
  const ClubAssignments({required this.athletes, required this.assignments});

  final List<ClubAthlete> athletes;
  final List<Assignment> assignments;

  List<Assignment> get active => [
    for (final a in assignments)
      if (a.status != AssignmentStatus.ended) a,
  ];

  List<Assignment> get ended => [
    for (final a in assignments)
      if (a.status == AssignmentStatus.ended) a,
  ];

  /// The name of the athlete [id]; "Atleta" when they are no longer in the club.
  String nameOf(String id) {
    for (final a in athletes) {
      if (a.id == id) return a.name;
    }
    return 'Atleta';
  }

  /// "Ari, Andi": the names of [ids], in that order.
  String namesOf(Iterable<String> ids) => ids.map(nameOf).join(', ');
}

Future<ClubAssignments> _loadClubAssignments(
  String? clubId,
  AssignmentRepository repo,
  AthleteRepository athletes,
) async {
  if (clubId == null) {
    return const ClubAssignments(athletes: [], assignments: []);
  }
  final people = await athletes.athletes(clubId);
  return ClubAssignments(
    athletes: [for (final a in people) (id: a.id, name: a.name)],
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

/// The athletes and assignments right now, for an action outside the assignments screen.
Future<ClubAssignments> fetchClubAssignments(WidgetRef ref) async {
  final clubId = (await ref.read(meProvider.future))?.activeClub?.club.id;
  return _loadClubAssignments(
    clubId,
    ref.read(assignmentRepositoryProvider),
    ref.read(athleteRepositoryProvider),
  );
}

/// Assigns [planId] to [athleteIds] in the active club and refreshes the screen. Errors propagate.
Future<void> assignPlan(
  WidgetRef ref, {
  required String planId,
  required List<String> athleteIds,
  required DateTime startDate,
}) async {
  final clubId = (await ref.read(meProvider.future))?.activeClub?.club.id;
  if (clubId == null) return;
  await ref
      .read(assignmentRepositoryProvider)
      .assign(
        clubId,
        planId: planId,
        athleteIds: athleteIds,
        startDate: startDate,
      );
  ref.invalidate(clubAssignmentsProvider);
}

/// Sets who does [assignmentId] from today on (E6.7) and refreshes the screen. Errors propagate.
Future<void> setAssignmentAthletes(
  WidgetRef ref,
  String assignmentId,
  List<String> athleteIds,
) async {
  final clubId = (await ref.read(meProvider.future))?.activeClub?.club.id;
  if (clubId == null) return;
  await ref
      .read(assignmentRepositoryProvider)
      .setAthletes(
        clubId,
        assignmentId,
        athleteIds: athleteIds,
        date: ref.read(assignmentTodayProvider),
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
