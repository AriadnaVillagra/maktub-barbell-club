import 'dart:async';

import 'package:maktub_core/maktub_core.dart';

/// How the changes of a session reach the devices following it (diseno, "Multi-dispositivo"). Slices use only this,
/// so a bus (Pub/Sub or similar) can replace the in-memory implementation if there is ever more than one instance.
abstract interface class LiveBroadcast {
  /// Runs [change] alone among the changes of [sessionId], and returns its result. Numbering, saving and publishing
  /// a change go inside: otherwise a change could get a number below one already seen, and a client resyncing
  /// from that higher number would never receive it.
  Future<T> inOrder<T>(String sessionId, Future<T> Function() change);

  /// Sends [change] to everyone following its session.
  void publish(SessionChange change);

  /// The changes of that session published from now on. A client that reconnects listens first and resyncs after,
  /// so nothing falls between the two.
  Stream<SessionChange> changesOf(String clubId, String sessionId);
}

/// Valid only because the service runs as a single instance (CLAUDE.md, "Architecture").
class MemoryLiveBroadcast implements LiveBroadcast {
  final _changes = StreamController<SessionChange>.broadcast();
  final _lastInLine = <String, Future<void>>{};

  @override
  Future<T> inOrder<T>(String sessionId, Future<T> Function() change) {
    final result = (_lastInLine[sessionId] ?? Future<void>.value()).then(
      (_) => change(),
    );
    // A failed change must not stop the ones behind it; its error reaches its own caller through [result].
    late final Future<void> done;
    done = result.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      if (identical(_lastInLine[sessionId], done)) {
        _lastInLine.remove(sessionId);
      }
    });
    _lastInLine[sessionId] = done;
    return result;
  }

  @override
  void publish(SessionChange change) => _changes.add(change);

  @override
  Stream<SessionChange> changesOf(String clubId, String sessionId) => _changes
      .stream
      .where((c) => c.clubId == clubId && c.sessionId == sessionId);
}
