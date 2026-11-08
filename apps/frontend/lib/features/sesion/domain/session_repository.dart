import 'package:maktub_core/maktub_core.dart';

import 'athlete_adjustments.dart';

/// The session of a day as the backend opens it, with what was recorded so far.
class LiveSession {
  const LiveSession({required this.session, required this.records});

  final Session session;
  final List<SetRecord> records;
}

abstract interface class SessionRepository {
  /// Opens or resumes the session of [day] of [week] of the assignment on [date], adding [presentAthleteIds].
  /// Throws `ErrorDeApi` with the backend's message when it refuses.
  Future<LiveSession> open(
    String clubId, {
    required String assignmentId,
    required DateTime date,
    required int week,
    required int day,
    required Set<String> presentAthleteIds,
  });

  /// The kilos proposed for every set of [athleteId] in [sessionId], resolved by the server with
  /// [adjustments]. The work factor comes only when the user can see it.
  Future<List<ProposedSet>> proposedLoads(
    String clubId,
    String sessionId,
    String athleteId,
    AthleteAdjustments adjustments,
  );
}
