import 'package:maktub_backend/features/sesion/live_tickets.dart';

/// What the "connect to a live session" slice reads and writes.
abstract interface class ConnectLiveSessionStore {
  /// Removes and returns the ticket under [value], or null if there is none. A ticket is returned only once.
  LiveTicket? takeTicket(String value);
}

class MemoryConnectLiveSessionStore implements ConnectLiveSessionStore {
  MemoryConnectLiveSessionStore(this._tickets);

  final LiveTickets _tickets;

  @override
  LiveTicket? takeTicket(String value) => _tickets.take(value);
}
