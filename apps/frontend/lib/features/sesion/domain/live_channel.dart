import 'package:maktub_core/maktub_core.dart';

/// One open connection to the live channel of a session (E7.5, E7.6).
abstract interface class LiveConnection {
  /// Every change of the session the server publishes while the connection is open, the device's own included. It
  /// ends when the connection closes for any reason: Cloud Run closes it about every 60 min with code 1006, the same
  /// as a network drop.
  Stream<SessionChange> get changes;

  Future<void> close();
}

/// What a resync answers: the changes after a number and the last number the session has given.
class ChangesSince {
  const ChangesSince({required this.last, required this.changes});

  final int last;

  /// In order and once each, with its current state.
  final List<SessionChange> changes;
}

/// The live channel of the sessions, as the backend offers it.
abstract interface class LiveChannel {
  /// Asks a single-use ticket and opens the session's WebSocket with it; the access token never goes in the URL.
  /// Throws when it cannot open.
  Future<LiveConnection> connect(String clubId, String sessionId);

  /// What changed in the session after number [since].
  Future<ChangesSince> changesSince(String clubId, String sessionId, int since);
}
