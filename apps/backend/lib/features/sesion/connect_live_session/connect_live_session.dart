import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:dart_frog_web_socket/dart_frog_web_socket.dart';
import 'package:maktub_backend/features/sesion/live_broadcast.dart';
import 'package:maktub_backend/features/sesion/live_tickets.dart';
import 'package:maktub_backend/features/sesion/record_view.dart';
import 'package:maktub_backend/infraestructura/http.dart';

import 'connect_live_session_store.dart';

/// `GET /vivo/clubes/{clubId}/sesiones/{sesionId}?ticket=…` → upgrades to the WebSocket of that session, or 401
/// before the upgrade if the ticket is not valid. The ticket is the only credential read here: the access token
/// never travels in the URL (diseno, "Multi-dispositivo").
///
/// The route lives outside `/clubes/{clubId}/…` because that group's middleware requires the `Authorization`
/// header, which a browser WebSocket cannot send. The club and the session are checked when the ticket is issued
/// and bound to it, so this reads nothing else.
///
/// The server sends each change of the session as a JSON `SessionChange`, to every connection including the device
/// that wrote it; the client ignores anything it sends. To lose nothing on reconnecting, a client connects first and
/// then asks `GET …/cambios?desde=N`. [store], [broadcast] and [now] are for tests.
Future<Response> connectLiveSessionEndpoint(
  RequestContext context,
  String clubId,
  String sessionId, {
  ConnectLiveSessionStore? store,
  LiveBroadcast? broadcast,
  DateTime Function()? now,
}) async {
  final ticket = ConnectLiveSession(
    store ?? MemoryConnectLiveSessionStore(context.read<LiveTickets>()),
    now: now,
  )(clubId, sessionId, context.request.uri.queryParameters['ticket']);
  final changes = (broadcast ?? context.read<LiveBroadcast>()).changesOf(
    clubId,
    sessionId,
  );
  final handler = webSocketHandler((channel, _) {
    final subscription = changes.listen(
      (change) => channel.sink.add(
        jsonEncode(changeForViewer(change, seesFactors: ticket.canSeeFactors)),
      ),
    );
    // Nothing the client sends matters, but the stream must be listened to for the close handshake to happen.
    channel.stream.listen(
      (_) {},
      onError: (Object _) {},
      onDone: subscription.cancel,
    );
  }, pingInterval: _pingInterval);
  return handler(context);
}

/// Finds dead connections and keeps an idle one alive through Cloud Run's proxy (E7.1 measured with 30 s).
const _pingInterval = Duration(seconds: 30);

class ConnectLiveSession {
  ConnectLiveSession(this._store, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final ConnectLiveSessionStore _store;
  final DateTime Function() _now;

  // One message for every reason, so a rejection does not tell which part of a guessed ticket was right.
  static const _invalid = ErrorDeSolicitud(
    'Ticket inválido.',
    estado: HttpStatus.unauthorized,
  );

  /// Throws a 401 unless [value] is a live ticket for exactly this club and session. Any presented ticket is
  /// consumed, even when it is rejected, so it can never be tried twice.
  LiveTicket call(String clubId, String sessionId, String? value) {
    if (value == null || value.isEmpty) throw _invalid;
    final ticket = _store.takeTicket(value);
    if (ticket == null ||
        ticket.clubId != clubId ||
        ticket.sessionId != sessionId ||
        ticket.isExpiredAt(_now().toUtc())) {
      throw _invalid;
    }
    return ticket;
  }
}
