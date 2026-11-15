import 'dart:async';

import 'package:maktub_core/maktub_core.dart';

import 'block_time_write.dart';
import 'session_draft_store.dart';
import 'session_repository.dart';
import 'set_write.dart';

/// Sends one queued write to the server and returns what it stored.
typedef SendSetWrite = Future<SetRecord> Function(PendingSetWrite pending);

/// Sends one queued block time to the server.
typedef SendBlockTime = Future<void> Function(PendingBlockTime pending);

/// Sends one queued write of the guided pass to the server and returns the session as the server left it.
typedef SendGuidedWrite = Future<Session> Function(PendingGuidedWrite pending);

/// Sends one queued opening to the server and returns the session it opened or resumed.
typedef SendSessionOpen = Future<LiveSession> Function(
  PendingSessionOpen pending,
);

/// A session opening that reached the server: [sessionId] is the id the device had for it, and [live] what the server
/// answered, whose id the queued writes now carry.
typedef SessionOpened = ({String sessionId, LiveSession live});

/// Whether what the device has queued reached the server, for the guided mode's header.
enum SaveState {
  /// Nothing is waiting.
  saved,

  /// Something is waiting and a pass is sending it.
  saving,

  /// Something is waiting and the last pass could not send it (no signal, server down).
  unsaved,
}

/// What one pass over the queue did, by the local id of each write.
class FlushOutcome {
  const FlushOutcome({
    this.opened = const {},
    this.stored = const {},
    this.rejected = const {},
  });

  /// The sessions the server opened, by the id the device had for each.
  final Map<String, LiveSession> opened;

  /// The writes the server took, with what it stored.
  final Map<String, SetRecord> stored;

  /// The writes the server refused. They leave the queue: sending them again would be refused again.
  final Map<String, Object> rejected;
}

/// Syncing the session's set writes (D8): each one goes first to the draft and the queue on the device, then to the
/// server, in order. Without signal it stays queued until [flush] runs again. The server's write is an idempotent
/// upsert per set (E7.3), so resending something it already took changes nothing.
///
/// The writes of the guided pass (E7.26) wait here behind the sets, and then the block times. The server applies each
/// pass write over the pass it has, so resending one is harmless.
///
/// The block times of the guided mode (E7.21) wait here too, after the sets: each has its own id, kept across
/// retries, and the server's write is an upsert by that id (E7.19), so a time never goes in twice.
///
/// The openings of sessions opened without signal (E7.16) go before everything else. The writes of such a session
/// carry the device's id until its opening goes through; then the queue gives them the server's id, and they leave
/// right after, in the same pass. Opening is idempotent on the server, so two devices that opened the same day
/// without signal end up writing to the one session the server has.
class SetSyncQueue {
  SetSyncQueue({
    required this.send,
    this.sendTime,
    this.sendGuided,
    this.sendOpen,
    required this.store,
    required this.isRetryable,
    this.sendTimeout = const Duration(seconds: 10),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SendSetWrite send;

  /// Without it, block times stay queued.
  final SendBlockTime? sendTime;

  /// Without it, the writes of the guided pass stay queued, and so do the block times behind them.
  final SendGuidedWrite? sendGuided;

  /// Without it, openings stay queued, and so does everything behind them.
  final SendSessionOpen? sendOpen;
  final SessionDraftStore store;

  /// Whether a failed send can go again later (no signal, server down) instead of being refused for good.
  final bool Function(Object error) isRetryable;
  final DateTime Function() _now;

  /// A write that takes longer counts as not sent and stays queued. If it did reach the server, resending is harmless.
  final Duration sendTimeout;

  final _changes = StreamController<List<PendingWrite>>.broadcast();
  final _opened = StreamController<SessionOpened>.broadcast();
  // Synchronous, so the screen takes the session the server answered before the write leaves [pendingGuided] and the
  // pass on screen never steps back in between.
  final _guidedStored = StreamController<Session>.broadcast(sync: true);
  late final Future<void> _restored = _restore();
  var _opens = <PendingSessionOpen>[];
  var _queue = <PendingSetWrite>[];
  var _times = <PendingBlockTime>[];
  var _guided = <PendingGuidedWrite>[];
  var _flushing = 0;
  var _stalled = false;
  final _draft = <SetKey, PendingSetWrite>{};
  Future<void> _tail = Future.value();
  var _counter = 0;

  /// The server's id of each session this device opened without signal, by the device's id, for the writes that
  /// were on their way while the opening went through.
  final _renamed = <String, String>{};

  /// Completes once what the device had stored is loaded.
  Future<void> get ready => _restored;

  /// The writes not yet taken by the server, in the order they will go.
  List<PendingSetWrite> get pending => List.unmodifiable(_queue);

  /// The block times not yet taken by the server.
  List<PendingBlockTime> get pendingTimes => List.unmodifiable(_times);

  /// The writes of the guided pass not yet taken by the server, in order.
  List<PendingGuidedWrite> get pendingGuided => List.unmodifiable(_guided);

  /// The openings not yet taken by the server.
  List<PendingSessionOpen> get pendingOpens => List.unmodifiable(_opens);

  /// Everything waiting for the server: the openings, the sets, the writes of the guided pass, then the block times.
  List<PendingWrite> get unsent => [
    ..._opens,
    ..._queue,
    ..._guided,
    ..._times,
  ];

  /// Emits [unsent] every time it or [saveState] changes.
  Stream<List<PendingWrite>> get changes => _changes.stream;

  /// Emits each opening once the server takes it, after the queued writes got the server's id.
  Stream<SessionOpened> get opened => _opened.stream;

  /// Emits, synchronously, the session the server answered to each write of the guided pass, before the write leaves
  /// the queue.
  Stream<Session> get guidedStored => _guidedStored.stream;

  /// The id [sessionId] goes by now: the server's when it was the device's id of a session opened since.
  String currentIdOf(String sessionId) => _renamed[sessionId] ?? sessionId;

  /// The opening still queued for the same day as [open], if any.
  Future<PendingSessionOpen?> openingLike(PendingSessionOpen open) async {
    await _restored;
    return _opens.where((o) => o.sameDay(open)).firstOrNull;
  }

  SaveState get saveState => _flushing > 0
      ? SaveState.saving
      : unsent.isEmpty
      ? SaveState.saved
      : _stalled
      ? SaveState.unsaved
      : SaveState.saving;

  /// The last local write of each set of [sessionId] that has not reached the server yet, to show over what the
  /// server returned when the session opens again. Forgets the draft of other sessions with nothing left to send.
  Future<List<SetWrite>> resume(String sessionId) async {
    await _restored;
    final unsent = {for (final p in _queue) p.key};
    _draft.removeWhere(
      (k, _) => k.sessionId != sessionId && !unsent.contains(k),
    );
    await _persist();
    return [
      for (final e in _draft.entries)
        if (e.key.sessionId == sessionId && unsent.contains(e.key))
          e.value.write,
    ];
  }

  /// Keeps [write] on the device and sends the queue. Returns what the server stored, or null when it stayed queued.
  /// Throws what the server answered when it refuses this write.
  Future<SetRecord?> submit({
    required String clubId,
    required String sessionId,
    required SetWrite write,
  }) async {
    await _restored;
    final pending = PendingSetWrite(
      id: '${_now().microsecondsSinceEpoch}-${_counter++}',
      clubId: clubId,
      sessionId: currentIdOf(sessionId),
      write: write,
    );
    _queue = [..._queue, pending];
    _draft[pending.key] = pending;
    _awaited.add(pending.id);
    try {
      await _persist();
      _emit();
      final outcome = await flush();
      final elsewhere = _settledElsewhere.remove(pending.id);
      if (outcome.rejected[pending.id] ?? elsewhere?.error case final error?) {
        throw error;
      }
      return outcome.stored[pending.id] ?? elsewhere?.stored;
    } finally {
      _awaited.remove(pending.id);
      _settledElsewhere.remove(pending.id);
    }
  }

  /// The writes a [submit] is waiting for, and what a flush that was not its own did with them: another flush (the
  /// live channel's, when it opens) may send a write between it being queued and its own flush.
  final _awaited = <String>{};
  final _settledElsewhere = <String, ({SetRecord? stored, Object? error})>{};

  void _settled(String id, {SetRecord? stored, Object? error}) {
    if (_awaited.contains(id)) {
      _settledElsewhere[id] = (stored: stored, error: error);
    }
  }

  /// Keeps the opening [open] on the device, ahead of every write, and sends the queue without waiting for it. An
  /// opening already queued for the same day keeps its session id and adds the present athletes of [open]. Returns
  /// the opening as queued.
  Future<PendingSessionOpen> submitOpen(PendingSessionOpen open) async {
    await _restored;
    final same = _opens.where((o) => o.sameDay(open)).firstOrNull;
    final queued = same?.adding(open.presentAthleteIds) ?? open;
    _opens = [
      for (final o in _opens) identical(o, same) ? queued : o,
      if (same == null) queued,
    ];
    await _persist();
    _emit();
    flush().ignore();
    return queued;
  }

  /// Keeps [write] on the device and sends the queue. The time goes out once however many passes it takes. [id] is
  /// the time's id on the server, taken from the guided pass (E7.26) so every device gives a block the same one; a time
  /// already queued with it is replaced. Returns the id the time was given.
  Future<String> submitBlockTime({
    required String clubId,
    required String sessionId,
    required BlockTimeWrite write,
    String? id,
  }) async {
    await _restored;
    final pending = PendingBlockTime(
      id: id ?? '${_now().microsecondsSinceEpoch}-${_counter++}',
      clubId: clubId,
      sessionId: currentIdOf(sessionId),
      write: write,
    );
    _times = [
      for (final t in _times)
        if (t.id != pending.id) t,
      pending,
    ];
    await _persist();
    _emit();
    await flush();
    return pending.id;
  }

  /// Keeps [action] on the device, behind the sets, and sends the queue without waiting for it: the guided mode moves
  /// on at once (E7.26). Returns the write as queued.
  Future<PendingGuidedWrite> submitGuided({
    required String clubId,
    required String sessionId,
    required GuidedPassAction action,
  }) async {
    await _restored;
    final pending = PendingGuidedWrite(
      id: '${_now().microsecondsSinceEpoch}-${_counter++}',
      clubId: clubId,
      sessionId: currentIdOf(sessionId),
      action: action,
    );
    _guided = [..._guided, pending];
    await _persist();
    _emit();
    flush().ignore();
    return pending;
  }

  /// Sends what is queued, in order, and stops at the first write that cannot go now (no signal, server down).
  /// Passes never overlap, so the order holds. Call it again when the connection comes back.
  Future<FlushOutcome> flush() {
    _flushing++;
    _emit();
    final run = _tail.then((_) => _flush()).whenComplete(() {
      _flushing--;
      _emit();
    });
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<FlushOutcome> _flush() async {
    await _restored;
    final opened = <String, LiveSession>{};
    final stored = <String, SetRecord>{};
    final rejected = <String, Object>{};
    _stalled = false;
    final sendOpen = this.sendOpen;
    while (_opens.isNotEmpty) {
      final head = _opens.first;
      if (sendOpen == null) {
        _stalled = true;
        break;
      }
      LiveSession? live;
      try {
        live = await sendOpen(head).timeout(sendTimeout);
      } on TimeoutException {
        _stalled = true;
        break;
      } catch (e) {
        if (isRetryable(e)) {
          _stalled = true;
          break;
        }
        rejected[head.id] = e;
      }
      _opens = [
        for (final o in _opens)
          if (!identical(o, head)) o,
      ];
      if (live == null) {
        _dropLocal(head.sessionId);
      } else {
        _rename(head.sessionId, live.session.id);
        opened[head.sessionId] = live;
      }
      await _persist();
      _emit();
      if (live != null && !_opened.isClosed) {
        _opened.add((sessionId: head.sessionId, live: live));
      }
    }
    while (!_stalled && _queue.isNotEmpty) {
      final head = _queue.first;
      try {
        final record = stored[head.id] = await send(head).timeout(sendTimeout);
        _settled(head.id, stored: record);
      } on TimeoutException {
        _stalled = true;
        break;
      } catch (e) {
        if (isRetryable(e)) {
          _stalled = true;
          break;
        }
        rejected[head.id] = e;
        _settled(head.id, error: e);
        if (_draft[head.key]?.id == head.id) _draft.remove(head.key);
      }
      _queue = [
        for (final p in _queue)
          if (p.id != head.id) p,
      ];
      await _persist();
      _emit();
    }
    final sendGuided = this.sendGuided;
    // Behind the sets, like the block times: a pass that closes a block arrives after the block's sets.
    while (!_stalled && _guided.isNotEmpty) {
      final head = _guided.first;
      if (sendGuided == null) {
        _stalled = true;
        break;
      }
      try {
        final session = await sendGuided(head).timeout(sendTimeout);
        if (!_guidedStored.isClosed) _guidedStored.add(session);
      } on TimeoutException {
        _stalled = true;
        break;
      } catch (e) {
        if (isRetryable(e)) {
          _stalled = true;
          break;
        }
        rejected[head.id] = e;
      }
      _guided = [
        for (final g in _guided)
          if (g.id != head.id) g,
      ];
      await _persist();
      _emit();
    }
    final sendTime = this.sendTime;
    // Behind the sets, so a session opened without signal has them first; and not at all while they are stuck.
    while (!_stalled && sendTime != null && _times.isNotEmpty) {
      final head = _times.first;
      try {
        await sendTime(head).timeout(sendTimeout);
      } on TimeoutException {
        _stalled = true;
        break;
      } catch (e) {
        if (isRetryable(e)) {
          _stalled = true;
          break;
        }
        rejected[head.id] = e;
      }
      _times = [
        for (final t in _times)
          if (t.id != head.id) t,
      ];
      await _persist();
      _emit();
    }
    return FlushOutcome(opened: opened, stored: stored, rejected: rejected);
  }

  /// Gives the writes of the session [from] the server's id [to].
  void _rename(String from, String to) {
    if (from == to) return;
    _renamed[from] = to;
    _queue = [
      for (final p in _queue) p.sessionId == from ? p.inSession(to) : p,
    ];
    _times = [
      for (final t in _times) t.sessionId == from ? t.inSession(to) : t,
    ];
    _guided = [
      for (final g in _guided) g.sessionId == from ? g.inSession(to) : g,
    ];
    final moved = [
      for (final p in _draft.values)
        if (p.sessionId == from) p.inSession(to),
    ];
    _draft.removeWhere((k, _) => k.sessionId == from);
    for (final p in moved) {
      _draft[p.key] = p;
    }
  }

  /// Forgets the writes of a session opened on the device whose opening the server refused: without the session they
  /// would be refused too.
  void _dropLocal(String sessionId) {
    if (!isLocalSessionId(sessionId)) return;
    _queue = [
      for (final p in _queue)
        if (p.sessionId != sessionId) p,
    ];
    _times = [
      for (final t in _times)
        if (t.sessionId != sessionId) t,
    ];
    _guided = [
      for (final g in _guided)
        if (g.sessionId != sessionId) g,
    ];
    _draft.removeWhere((k, _) => k.sessionId == sessionId);
  }

  Future<void> _restore() async {
    try {
      final snapshot = await store.load();
      _opens = [...snapshot.opens];
      _queue = [...snapshot.queue];
      _times = [...snapshot.times];
      _guided = [...snapshot.guided];
      for (final p in snapshot.draft) {
        _draft[p.key] = p;
      }
    } catch (_) {
      // No local storage: the queue still works, only in memory.
    }
    _emit();
  }

  Future<void> _persist() async {
    try {
      await store.save(
        DraftSnapshot(
          draft: _draft.values.toList(),
          opens: _opens,
          queue: _queue,
          guided: _guided,
          times: _times,
        ),
      );
    } catch (_) {
      // No local storage: what is in memory still goes out.
    }
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(unsent);
  }

  void dispose() {
    _changes.close();
    _opened.close();
    _guidedStored.close();
  }
}
