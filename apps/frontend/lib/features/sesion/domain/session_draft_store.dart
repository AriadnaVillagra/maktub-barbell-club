import 'package:maktub_core/maktub_core.dart';

import 'set_write.dart';

/// One set write for one session, as the device keeps it until the server takes it.
class PendingSetWrite {
  const PendingSetWrite({
    required this.id,
    required this.clubId,
    required this.sessionId,
    required this.write,
  });

  /// Local id, only to tell queued writes apart. The server never sees it.
  final String id;
  final String clubId;
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

/// Identifies one set of one athlete in one session.
typedef SetKey = ({
  String sessionId,
  String athleteId,
  int blockIndex,
  int prescriptionIndex,
  int setIndex,
});

/// What the device keeps: the draft (the last local write of each set) and the queue of writes not yet sent, in order.
class DraftSnapshot {
  const DraftSnapshot({this.draft = const [], this.queue = const []});

  final List<PendingSetWrite> draft;
  final List<PendingSetWrite> queue;

  Json toJson() => {
    'borrador': [for (final w in draft) w.toJson()],
    'cola': [for (final w in queue) w.toJson()],
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
  );
}

/// The device's local storage for the session's draft and queue. Best effort: without storage, [load] gives an
/// empty snapshot and [save] does nothing, so the app keeps working without the draft.
abstract interface class SessionDraftStore {
  Future<DraftSnapshot> load();

  Future<void> save(DraftSnapshot snapshot);
}
