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

/// Identifies one set of one athlete in one session.
typedef SetKey = ({
  String sessionId,
  String athleteId,
  int blockIndex,
  int prescriptionIndex,
  int setIndex,
});

/// What the device keeps: the draft (the last local write of each set), the queue of set writes not yet sent, in
/// order, and the block times not yet sent.
class DraftSnapshot {
  const DraftSnapshot({
    this.draft = const [],
    this.queue = const [],
    this.times = const [],
  });

  final List<PendingSetWrite> draft;
  final List<PendingSetWrite> queue;
  final List<PendingBlockTime> times;

  Json toJson() => {
    'borrador': [for (final w in draft) w.toJson()],
    'cola': [for (final w in queue) w.toJson()],
    'tiempos': [for (final t in times) t.toJson()],
  };

  factory DraftSnapshot.fromJson(Json j) => DraftSnapshot(
    draft: [
      for (final w in (j['borrador'] as List? ?? const []))
        PendingSetWrite.fromJson((w as Map).cast<String, dynamic>()),
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
