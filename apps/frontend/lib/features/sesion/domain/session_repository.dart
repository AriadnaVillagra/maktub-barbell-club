import 'package:maktub_core/maktub_core.dart';

import 'athlete_adjustments.dart';
import 'block_time_write.dart';
import 'set_write.dart';

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

  /// Writes that one set and returns what is stored. Repeating it changes nothing.
  Future<SetRecord> recordSet(String clubId, String sessionId, SetWrite write);

  /// Writes the time of one block under [timeId], chosen by the client. Repeating it changes nothing.
  Future<void> recordBlockTime(
    String clubId,
    String sessionId,
    String timeId,
    BlockTimeWrite write,
  );

  /// Writes the note of the whole session, or clears it when [note] is empty.
  Future<Session> saveSessionNote(String clubId, String sessionId, String note);
}
