import 'dart:async';
import 'dart:convert';

import 'package:maktub_core/maktub_core.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/red/cliente_api.dart';
import '../domain/live_channel.dart';

/// Opens a WebSocket. Tests replace it.
typedef OpenWebSocket = WebSocketChannel Function(Uri uri);

/// The live channel over the backend's WebSocket (E7.5, E7.6). The ticket is asked with the access token in the
/// `Authorization` header, like any request; only the ticket goes in the WebSocket's URL.
class WebSocketLiveChannel implements LiveChannel {
  WebSocketLiveChannel(this._client, {OpenWebSocket? open})
    : _open = open ?? WebSocketChannel.connect;

  final ClienteApi _client;
  final OpenWebSocket _open;

  static String _session(String clubId, String sessionId) =>
      '/clubes/${Uri.encodeComponent(clubId)}/sesiones/${Uri.encodeComponent(sessionId)}';

  @override
  Future<LiveConnection> connect(String clubId, String sessionId) async {
    final j = await _client.post('${_session(clubId, sessionId)}/ticket');
    final socket = _open(
      liveUri(_client.base, clubId, sessionId, '${j['ticket']}'),
    );
    try {
      await socket.ready;
    } catch (e) {
      unawaited(socket.sink.close());
      throw ErrorDeApi('No se pudo abrir el canal en vivo ($e).');
    }
    return _WebSocketConnection(socket);
  }

  @override
  Future<ChangesSince> changesSince(
    String clubId,
    String sessionId,
    int since,
  ) async {
    final j = await _client.get(
      '${_session(clubId, sessionId)}/cambios?desde=$since',
    );
    return ChangesSince(
      last: (j['secuencia'] as num?)?.toInt() ?? since,
      changes: [
        for (final c in (j['cambios'] as List? ?? const []))
          SessionChange.fromJson((c as Map).cast<String, dynamic>()),
      ],
    );
  }
}

/// The WebSocket URL of a session's live channel on the API at [base]: `ws` for `http`, `wss` for `https`.
Uri liveUri(Uri base, String clubId, String sessionId, String ticket) =>
    base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      pathSegments: [
        ...base.pathSegments.where((s) => s.isNotEmpty),
        'vivo',
        'clubes',
        clubId,
        'sesiones',
        sessionId,
      ],
      queryParameters: {'ticket': ticket},
    );

class _WebSocketConnection implements LiveConnection {
  _WebSocketConnection(this._socket);

  final WebSocketChannel _socket;

  @override
  late final Stream<SessionChange> changes = _socket.stream
      .map(_parse)
      .where((c) => c != null)
      .cast<SessionChange>();

  /// Something unreadable is skipped: the next resync brings the state anyway.
  static SessionChange? _parse(Object? message) {
    try {
      return SessionChange.fromJson(
        (jsonDecode('$message') as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> close() async {
    // Not awaited: on a dead connection the close handshake may never finish, and reconnecting must not wait for it.
    unawaited(_socket.sink.close().then((_) {}, onError: (Object _) {}));
  }
}
