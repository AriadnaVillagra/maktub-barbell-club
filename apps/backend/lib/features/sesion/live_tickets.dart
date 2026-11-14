/// One-use tickets that authenticate the live channel of a session (diseno, "Multi-dispositivo").
///
/// A browser WebSocket cannot send an `Authorization` header and the app and the API are on different sites, so
/// there are no cookies either. A device asks for a ticket over HTTP with its access token and presents the ticket
/// when it opens the socket. The ticket can go in the URL because it dies on first use and within seconds; the
/// access token never does.
library;

/// Long enough for a phone on a bad connection to open the socket right after asking for the ticket.
const liveTicketLifetime = Duration(seconds: 30);

/// What a ticket lets one connection do: follow [sessionId] of [clubId], as [userId], until [expiresAt].
class LiveTicket {
  const LiveTicket({
    required this.clubId,
    required this.sessionId,
    required this.userId,
    required this.expiresAt,
    this.canSeeFactors = false,
  });

  final String clubId;
  final String sessionId;
  final String userId;
  final DateTime expiresAt;

  /// Whether the changes sent over this connection include work factors.
  final bool canSeeFactors;

  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);
}

/// Tickets waiting to be used, in memory: the service runs as a single instance, a ticket lives for seconds, and a
/// restart only makes the client ask for another one.
class LiveTickets {
  final _pending = <String, LiveTicket>{};

  /// Stores [ticket] under [value] and drops the expired ones, which nobody will ever come to take.
  void save(String value, LiveTicket ticket, {required DateTime now}) {
    _pending
      ..removeWhere((_, t) => t.isExpiredAt(now))
      ..[value] = ticket;
  }

  /// Removes and returns the ticket under [value]. It has no `await`, so two connections racing for one ticket
  /// cannot both get it.
  LiveTicket? take(String value) => _pending.remove(value);
}
