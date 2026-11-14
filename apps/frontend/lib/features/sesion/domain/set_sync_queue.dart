import 'dart:async';

import 'package:maktub_core/maktub_core.dart';

import 'session_draft_store.dart';
import 'set_write.dart';

/// Sends one queued write to the server and returns what it stored.
typedef SendSetWrite = Future<SetRecord> Function(PendingSetWrite pending);

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
class SetSyncQueue {
  SetSyncQueue({
    required this.send,
    required this.store,
    required this.isRetryable,
    this.sendTimeout = const Duration(seconds: 10),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SendSetWrite send;
  final SessionDraftStore store;

  /// Whether a failed send can go again later (no signal, server down) instead of being refused for good.
  final bool Function(Object error) isRetryable;
  final DateTime Function() _now;

  /// A write that takes longer counts as not sent and stays queued. If it did reach the server, resending is harmless.
  final Duration sendTimeout;

  final _changes = StreamController<List<PendingSetWrite>>.broadcast();
  late final Future<void> _restored = _restore();
  var _queue = <PendingSetWrite>[];
  final _draft = <SetKey, PendingSetWrite>{};
  Future<void> _tail = Future.value();
  var _counter = 0;

  /// Completes once what the device had stored is loaded.
  Future<void> get ready => _restored;

  /// The writes not yet taken by the server, in the order they will go.
  List<PendingSetWrite> get pending => List.unmodifiable(_queue);

  /// Emits [pending] every time it changes.
  Stream<List<PendingSetWrite>> get changes => _changes.stream;

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

  /// Sends what is queued, in order, and stops at the first write that cannot go now (no signal, server down).
  /// Passes never overlap, so the order holds. Call it again when the connection comes back.
  Future<FlushOutcome> flush() {
    final run = _tail.then((_) => _flush());
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<FlushOutcome> _flush() async {
    await _restored;
    final stored = <String, SetRecord>{};
    final rejected = <String, Object>{};
    while (_queue.isNotEmpty) {
      final head = _queue.first;
      try {
        stored[head.id] = await send(head).timeout(sendTimeout);
      } on TimeoutException {
        break;
      } catch (e) {
        if (isRetryable(e)) break;
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
    return FlushOutcome(stored: stored, rejected: rejected);
  }

  Future<void> _restore() async {
    try {
      final snapshot = await store.load();
      _queue = [...snapshot.queue];
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
        DraftSnapshot(draft: _draft.values.toList(), queue: _queue),
      );
    } catch (_) {
      // No local storage: what is in memory still goes out.
    }
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(pending);
  }

  void dispose() => _changes.close();
}
