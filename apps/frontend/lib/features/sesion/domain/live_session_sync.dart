import 'dart:async';

import 'package:maktub_core/maktub_core.dart';

import 'live_channel.dart';
import 'session_repository.dart';

/// Where the device stands with the live channel of the open session.
enum LiveStatus {
  /// Opening the channel for the first time (the service may be starting cold, 1–2 s).
  connecting,

  /// Connected and resynced: what other devices mark arrives at once.
  live,

  /// The channel closed and the device is opening it again. Not an error: Cloud Run closes it about every hour.
  reconnecting,

  /// Stopped for good: the server refuses the session or the screen left it.
  stopped,
}

/// Follows the live channel of one session (E7.10): connects, then resyncs from the highest number seen, and applies
/// every change as it arrives. When the channel closes it connects again by itself and resyncs, so a drop loses
/// nothing. Marking a set never waits for any of this: writes go through the queue (E7.9).
class LiveSessionSync {
  LiveSessionSync({
    required this.channel,
    required this.clubId,
    required this.sessionId,
    required int since,
    required this.onChanges,
    this.onConnected,
    this.isFinal = _never,
    this.backoff = defaultBackoff,
  }) : _lastSeen = since;

  /// The waits between attempts to reconnect; the last one repeats. The first is short because a periodic close by
  /// Cloud Run is the usual cause.
  static const defaultBackoff = [
    Duration(milliseconds: 500),
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];

  final LiveChannel channel;
  final String clubId;
  final String sessionId;

  /// Receives the changes that arrive, through the channel or a resync, in the order they came.
  final void Function(List<SessionChange> changes) onChanges;

  /// Called each time the channel opens, before the resync. The queue of writes goes out again from here.
  final void Function()? onConnected;

  /// Whether an error means trying again is pointless (the session is gone or not the user's).
  final bool Function(Object error) isFinal;
  final List<Duration> backoff;

  int _lastSeen;
  var _status = LiveStatus.connecting;
  var _started = false;
  var _stopped = false;
  LiveConnection? _connection;
  Timer? _sleep;
  Completer<void>? _woken;
  final _statusChanges = StreamController<LiveStatus>.broadcast();

  /// The highest change number seen. Numbers can skip, so a gap is not a loss.
  int get lastSeen => _lastSeen;

  LiveStatus get status => _status;
  Stream<LiveStatus> get statusChanges => _statusChanges.stream;

  void start() {
    if (_started) return;
    _started = true;
    unawaited(_run());
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _sleep?.cancel();
    if (_woken case final w? when !w.isCompleted) w.complete();
    _setStatus(LiveStatus.stopped);
    final connection = _connection;
    _connection = null;
    await _statusChanges.close();
    await connection?.close();
  }

  Future<void> _run() async {
    var attempt = 0;
    while (!_stopped) {
      try {
        if (await _follow()) attempt = 0;
      } catch (e) {
        if (isFinal(e)) {
          await stop();
          return;
        }
      }
      if (_stopped) return;
      _setStatus(LiveStatus.reconnecting);
      await _wait(
        backoff[attempt < backoff.length ? attempt : backoff.length - 1],
      );
      attempt++;
    }
  }

  /// One connection, from opening to closing. True when it got to resync, so the next wait starts short again.
  Future<bool> _follow() async {
    final connection = await channel.connect(clubId, sessionId);
    if (_stopped) {
      await connection.close();
      return false;
    }
    _connection = connection;
    final closed = Completer<void>();
    void done() {
      if (!closed.isCompleted) closed.complete();
    }

    final subscription = connection.changes.listen(
      (c) => _receive([c]),
      onError: (Object _) => done(),
      onDone: done,
    );
    var resynced = false;
    try {
      // Listening first and resyncing after leaves no gap: anything published meanwhile arrives by one or the other.
      onConnected?.call();
      final page = await channel.changesSince(clubId, sessionId, _lastSeen);
      if (_stopped) return false;
      _receive(page.changes);
      if (page.last > _lastSeen) _lastSeen = page.last;
      resynced = true;
      if (!closed.isCompleted) _setStatus(LiveStatus.live);
      await closed.future;
    } finally {
      await subscription.cancel();
      if (identical(_connection, connection)) _connection = null;
      await connection.close();
    }
    return resynced;
  }

  void _receive(List<SessionChange> changes) {
    if (_stopped || changes.isEmpty) return;
    for (final c in changes) {
      if (c.sequence > _lastSeen) _lastSeen = c.sequence;
    }
    onChanges(changes);
  }

  Future<void> _wait(Duration duration) {
    final woken = _woken = Completer<void>();
    _sleep = Timer(duration, () {
      if (!woken.isCompleted) woken.complete();
    });
    return woken.future;
  }

  void _setStatus(LiveStatus status) {
    if (_status == status) return;
    _status = status;
    if (!_statusChanges.isClosed) _statusChanges.add(status);
  }
}

bool _never(Object _) => false;

/// [live] with [changes] applied. A change older than what the session already holds for its record (or for the
/// session itself) is left out, so a resync answered after a newer change arrived never takes it back.
LiveSession applyChanges(LiveSession live, Iterable<SessionChange> changes) {
  var session = live.session;
  final records = [...live.records];
  for (final change in changes) {
    if (change.sessionId != session.id) continue;
    if (change.session case final s?) {
      if (s.lastSessionChange >= session.lastSessionChange) session = s;
      continue;
    }
    final record = change.record!;
    final i = records.indexWhere((r) => sameSet(r, record));
    if (i < 0) {
      records.add(record);
    } else if (isNewer(record, records[i])) {
      records[i] = record;
    }
  }
  return LiveSession(session: session, records: records);
}

/// Whether [incoming] is at least as recent as [current], by the change number that last wrote each. A record
/// without a number (shown before the server answered) gives way.
bool isNewer(SetRecord incoming, SetRecord current) =>
    current.sequence == null ||
    incoming.sequence == null ||
    incoming.sequence! >= current.sequence!;

/// Whether two records are of the same set: athlete, block, prescription and set.
bool sameSet(SetRecord a, SetRecord b) =>
    a.athleteId == b.athleteId &&
    a.blockIndex == b.blockIndex &&
    a.prescriptionIndex == b.prescriptionIndex &&
    a.setIndex == b.setIndex;
