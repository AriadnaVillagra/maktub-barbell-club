import 'package:maktub_core/maktub_core.dart';

import 'block_time_write.dart';
import 'set_write.dart';

/// Something the device keeps for the server until it takes it.
sealed class PendingWrite {
  const PendingWrite();

  /// Local id, only to tell queued writes apart.
  String get id;
  String get clubId;

  /// The session it belongs to. A session opened without signal (E7.16) has a local id here until the server's
  /// answer replaces it.
  String get sessionId;
}

/// One set write for one session, as the device keeps it until the server takes it.
class PendingSetWrite extends PendingWrite {
  const PendingSetWrite({
    required this.id,
    required this.clubId,
    required this.sessionId,
    required this.write,
  });

  /// The server never sees the id.
  @override
  final String id;
  @override
  final String clubId;
  @override
  final String sessionId;
  final SetWrite write;

  /// The same write for the session [sessionId], once the server gave the session opened on the device its id.
  PendingSetWrite inSession(String sessionId) => PendingSetWrite(
    id: id,
    clubId: clubId,
    sessionId: sessionId,
    write: write,
  );

  /// The set this write is for: the same key on the server's upsert.
  SetKey get key => (
    sessionId: sessionId,
    athleteId: write.athleteId,
    blockIndex: write.blockIndex,
    prescriptionIndex: write.prescriptionIndex,
    setIndex: write.setIndex,
  );

  Json toJson() => {
    'id': id,
    'clubId': clubId,
    'sesionId': sessionId,
    'escritura': write.toJson(),
  };

  factory PendingSetWrite.fromJson(Json j) => PendingSetWrite(
    id: '${j['id']}',
    clubId: '${j['clubId']}',
    sessionId: '${j['sesionId']}',
    write: SetWrite.fromJson((j['escritura'] as Map).cast<String, dynamic>()),
  );
}

/// One block time for one session. Its [id] is generated once, when the block closes, and is also the time's id on
/// the server (E7.19), so every retry rewrites the same document.
class PendingBlockTime extends PendingWrite {
  const PendingBlockTime({
    required this.id,
    required this.clubId,
    required this.sessionId,
    required this.write,
  });

  @override
  final String id;
  @override
  final String clubId;
  @override
  final String sessionId;
  final BlockTimeWrite write;

  /// The same time for the session [sessionId], once the server gave the session opened on the device its id.
  PendingBlockTime inSession(String sessionId) => PendingBlockTime(
    id: id,
    clubId: clubId,
    sessionId: sessionId,
    write: write,
  );

  Json toJson() => {
    'id': id,
    'clubId': clubId,
    'sesionId': sessionId,
    'tiempo': write.toJson(),
  };

  factory PendingBlockTime.fromJson(Json j) => PendingBlockTime(
    id: '${j['id']}',
    clubId: '${j['clubId']}',
    sessionId: '${j['sesionId']}',
    write: BlockTimeWrite.fromJson(
      (j['tiempo'] as Map).cast<String, dynamic>(),
    ),
  );
}

/// The ids the device gives the sessions it opens without signal (E7.16) start with this. The server never sees
/// them: the queue swaps them for the server's id as soon as the opening goes through.
const localSessionPrefix = 'local-';

/// Whether [sessionId] was given by this device to a session the server does not know yet.
bool isLocalSessionId(String sessionId) =>
    sessionId.startsWith(localSessionPrefix);

/// The opening of the session of one day, kept on the device until the server takes it (E7.16). It goes before
/// every set and time: opening is an idempotent upsert by assignment, date, week and day (E7.3), so if another
/// device opened the same day the server answers with that session and the queue moves this device's writes to it.
///
/// [sessionId] is the device's id ([isLocalSessionId]) for a session opened without signal, or the server's id when
/// the session was already known and only the present athletes chosen without signal have to travel.
class PendingSessionOpen extends PendingWrite {
  const PendingSessionOpen({
    required this.clubId,
    required this.sessionId,
    required this.assignmentId,
    required this.date,
    required this.week,
    required this.day,
    required this.presentAthleteIds,
  });

  @override
  final String clubId;
  @override
  final String sessionId;
  final String assignmentId;

  /// Calendar date (`DateTime.utc(y, m, d)`).
  final DateTime date;
  final int week;
  final int day;
  final List<String> presentAthleteIds;

  /// One opening per session, so its id is the session's.
  @override
  String get id => sessionId;

  /// Whether [other] opens the same day: the server's key of the session.
  bool sameDay(PendingSessionOpen other) =>
      clubId == other.clubId &&
      assignmentId == other.assignmentId &&
      date == other.date &&
      week == other.week &&
      day == other.day;

  /// This opening with [present] added to its athletes.
  PendingSessionOpen adding(Iterable<String> present) => PendingSessionOpen(
    clubId: clubId,
    sessionId: sessionId,
    assignmentId: assignmentId,
    date: date,
    week: week,
    day: day,
    presentAthleteIds: {...presentAthleteIds, ...present}.toList(),
  );

  Json toJson() => {
    'clubId': clubId,
    'sesionId': sessionId,
    'asignacionId': assignmentId,
    'fecha': aIsoFecha(date),
    'semana': week,
    'dia': day,
    'presentes': presentAthleteIds,
  };

  factory PendingSessionOpen.fromJson(Json j) => PendingSessionOpen(
    clubId: '${j['clubId']}',
    sessionId: '${j['sesionId']}',
    assignmentId: '${j['asignacionId']}',
    date: desdeIsoFecha('${j['fecha']}'),
    week: (j['semana'] as num).toInt(),
    day: (j['dia'] as num).toInt(),
    presentAthleteIds: [for (final a in (j['presentes'] as List)) '$a'],
  );
}

/// Identifies one set of one athlete in one session.
typedef SetKey = ({
  String sessionId,
  String athleteId,
  int blockIndex,
  int prescriptionIndex,
  int setIndex,
});

/// What the device keeps: the draft (the last local write of each set), the openings of sessions not yet sent, the
/// queue of set writes not yet sent, in order, and the block times not yet sent.
class DraftSnapshot {
  const DraftSnapshot({
    this.draft = const [],
    this.opens = const [],
    this.queue = const [],
    this.times = const [],
  });

  final List<PendingSetWrite> draft;
  final List<PendingSessionOpen> opens;
  final List<PendingSetWrite> queue;
  final List<PendingBlockTime> times;

  Json toJson() => {
    'borrador': [for (final w in draft) w.toJson()],
    'aperturas': [for (final o in opens) o.toJson()],
    'cola': [for (final w in queue) w.toJson()],
    'tiempos': [for (final t in times) t.toJson()],
  };

  factory DraftSnapshot.fromJson(Json j) => DraftSnapshot(
    draft: [
      for (final w in (j['borrador'] as List? ?? const []))
        PendingSetWrite.fromJson((w as Map).cast<String, dynamic>()),
    ],
    opens: [
      for (final o in (j['aperturas'] as List? ?? const []))
        PendingSessionOpen.fromJson((o as Map).cast<String, dynamic>()),
    ],
    queue: [
      for (final w in (j['cola'] as List? ?? const []))
        PendingSetWrite.fromJson((w as Map).cast<String, dynamic>()),
    ],
    times: [
      for (final t in (j['tiempos'] as List? ?? const []))
        PendingBlockTime.fromJson((t as Map).cast<String, dynamic>()),
    ],
  );
}

/// The device's local storage for the session's draft and queue. Best effort: without storage, [load] gives an
/// empty snapshot and [save] does nothing, so the app keeps working without the draft.
abstract interface class SessionDraftStore {
  Future<DraftSnapshot> load();

  Future<void> save(DraftSnapshot snapshot);
}
