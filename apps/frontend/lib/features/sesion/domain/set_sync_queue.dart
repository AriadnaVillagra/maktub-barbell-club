import 'dart:async';

import 'package:maktub_core/maktub_core.dart';

import 'block_time_write.dart';
import 'session_draft_store.dart';
import 'set_write.dart';

/// Sends one queued write to the server and returns what it stored.
typedef SendSetWrite = Future<SetRecord> Function(PendingSetWrite pending);

/// Sends one queued block time to the server.
typedef SendBlockTime = Future<void> Function(PendingBlockTime pending);

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
  const FlushOutcome({this.stored = const {}, this.rejected = const {}});

  /// The writes the server took, with what it stored.
  final Map<String, SetRecord> stored;

  /// The writes the server refused. They leave the queue: sending them again would be refused again.
  final Map<String, Object> rejected;
}

/// Syncing the session's set writes (D8): each one goes first to the draft and the queue on the device, then to the
/// server, in order. Without signal it stays queued until [flush] runs again. The server's write is an idempotent
/// upsert per set (E7.3), so resending something it already took changes nothing.
///
/// The block times of the guided mode (E7.21) wait here too, after the sets: each has its own id, kept across
/// retries, and the server's write is an upsert by that id (E7.19), so a time never goes in twice.
class SetSyncQueue {
  SetSyncQueue({
    required this.send,
    this.sendTime,
    required this.store,
    required this.isRetryable,
    this.sendTimeout = const Duration(seconds: 10),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SendSetWrite send;

  /// Without it, block times stay queued.
  final SendBlockTime? sendTime;
  final SessionDraftStore store;

  /// Whether a failed send can go again later (no signal, server down) instead of being refused for good.
  final bool Function(Object error) isRetryable;
  final DateTime Function() _now;

  /// A write that takes longer counts as not sent and stays queued. If it did reach the server, resending is harmless.
  final Duration sendTimeout;

  final _changes = StreamController<List<PendingWrite>>.broadcast();
  late final Future<void> _restored = _restore();
  var _queue = <PendingSetWrite>[];
  var _times = <PendingBlockTime>[];
  var _flushing = 0;
  var _stalled = false;
  final _draft = <SetKey, PendingSetWrite>{};
  Future<void> _tail = Future.value();
  var _counter = 0;

  /// Completes once what the device had stored is loaded.
  Future<void> get ready => _restored;

  /// The writes not yet taken by the server, in the order they will go.
  List<PendingSetWrite> get pending => List.unmodifiable(_queue);

  /// The block times not yet taken by the server.
  List<PendingBlockTime> get pendingTimes => List.unmodifiable(_times);

  /// Everything waiting for the server: the sets, then the block times.
  List<PendingWrite> get unsent => [..._queue, ..._times];

  /// Emits [unsent] every time it or [saveState] changes.
  Stream<List<PendingWrite>> get changes => _changes.stream;

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
      sessionId: sessionId,
      write: write,
    );
    _queue = [..._queue, pending];
    _draft[pending.key] = pending;
    await _persist();
    _emit();
    final outcome = await flush();
    if (outcome.rejected[pending.id] case final error?) throw error;
    return outcome.stored[pending.id];
  }

  /// Keeps [write] on the device and sends the queue. The time goes out once however many passes it takes. Returns
  /// the id the time was given.
  Future<String> submitBlockTime({
    required String clubId,
    required String sessionId,
    required BlockTimeWrite write,
  }) async {
    await _restored;
    final pending = PendingBlockTime(
      id: '${_now().microsecondsSinceEpoch}-${_counter++}',
      clubId: clubId,
      sessionId: sessionId,
      write: write,
    );
    _times = [..._times, pending];
    await _persist();
    _emit();
    await flush();
    return pending.id;
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
    final stored = <String, SetRecord>{};
    final rejected = <String, Object>{};
    _stalled = false;
    while (_queue.isNotEmpty) {
      final head = _queue.first;
      try {
        stored[head.id] = await send(head).timeout(sendTimeout);
      } on TimeoutException {
        _stalled = true;
        break;
      } catch (e) {
        if (isRetryable(e)) {
          _stalled = true;
          break;
        }
        rejected[head.id] = e;
        if (_draft[head.key]?.id == head.id) _draft.remove(head.key);
      }
      _queue = [
        for (final p in _queue)
          if (p.id != head.id) p,
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
    return FlushOutcome(stored: stored, rejected: rejected);
  }

  Future<void> _restore() async {
    try {
      final snapshot = await store.load();
      _queue = [...snapshot.queue];
      _times = [...snapshot.times];
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
          queue: _queue,
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

  void dispose() => _changes.close();
}
