import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/auth/tokens.dart';
import 'package:maktub_backend/features/sesion/connect_live_session/connect_live_session.dart';
import 'package:maktub_backend/features/sesion/connect_live_session/connect_live_session_store.dart';
import 'package:maktub_backend/features/sesion/live_broadcast.dart';
import 'package:maktub_backend/features/sesion/live_tickets.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

void main() {
  final issuedAt = DateTime.utc(2026, 11, 8, 18);
  late DateTime now;
  late LiveTickets tickets;
  late MemoryLiveBroadcast broadcast;
  late HttpServer server;

  void issue(
    String value, {
    String clubId = 'c1',
    String sessionId = 's1',
    bool canSeeFactors = false,
  }) {
    tickets.save(
      value,
      LiveTicket(
        clubId: clubId,
        sessionId: sessionId,
        userId: 'u1',
        expiresAt: issuedAt.add(liveTicketLifetime),
        canSeeFactors: canSeeFactors,
      ),
      now: issuedAt,
    );
  }

  /// Opens the channel of [path] through a real server, the same way a browser would.
  Future<WebSocket> connect(String path) =>
      WebSocket.connect('ws://localhost:${server.port}/$path');

  Matcher rejected() => throwsA(
    isA<WebSocketException>().having(
      (e) => e.httpStatusCode,
      'status',
      HttpStatus.unauthorized,
    ),
  );

  setUp(() async {
    now = issuedAt;
    tickets = LiveTickets();
    broadcast = MemoryLiveBroadcast();
    server = await serve(
      // Behind the same error and CORS middleware as the real route.
      manejarErrores()(
        cors()((context) {
          final segments = context.request.uri.pathSegments;
          return connectLiveSessionEndpoint(
            context,
            segments[0],
            segments[1],
            store: MemoryConnectLiveSessionStore(tickets),
            broadcast: broadcast,
            now: () => now,
          );
        }),
      ),
      'localhost',
      0,
    );
  });

  tearDown(() => server.close(force: true));

  test('a valid ticket opens the socket and it stays open', () async {
    issue('t1');

    final socket = await connect('c1/s1?ticket=t1');
    addTearDown(socket.close);

    expect(socket.readyState, WebSocket.open);
    socket.add('hello');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(socket.readyState, WebSocket.open);
  });

  test('closing the socket completes the close handshake', () async {
    issue('t1');
    final socket = await connect('c1/s1?ticket=t1');
    final closed = socket.drain<void>();

    await socket.close(WebSocketStatus.normalClosure);
    await closed.timeout(const Duration(seconds: 5));

    expect(socket.closeCode, WebSocketStatus.normalClosure);
  });

  test('a ticket serves one connection: the second is rejected', () async {
    issue('t1');
    final first = await connect('c1/s1?ticket=t1');
    addTearDown(first.close);

    await expectLater(connect('c1/s1?ticket=t1'), rejected());
  });

  test('of two connections racing for one ticket, only one opens', () async {
    issue('t1');

    final results = await Future.wait([
      for (var i = 0; i < 2; i++)
        connect('c1/s1?ticket=t1')
            .then<WebSocket?>((s) => s, onError: (Object _) => null),
    ]);

    final opened = results.nonNulls.toList();
    expect(opened, hasLength(1));
    await opened.single.close();
  });

  test('an expired ticket is rejected', () async {
    issue('t1');
    now = issuedAt.add(liveTicketLifetime);

    await expectLater(connect('c1/s1?ticket=t1'), rejected());
  });

  test('a ticket is valid until just before it expires', () async {
    issue('t1');
    now = issuedAt.add(liveTicketLifetime - const Duration(milliseconds: 1));

    final socket = await connect('c1/s1?ticket=t1');
    addTearDown(socket.close);

    expect(socket.readyState, WebSocket.open);
  });

  test('a ticket of another session is rejected', () async {
    issue('t1');

    await expectLater(connect('c1/s2?ticket=t1'), rejected());
  });

  test('a ticket of another club is rejected', () async {
    issue('t1');

    await expectLater(connect('c2/s1?ticket=t1'), rejected());
  });

  test('a ticket tried on the wrong session is spent', () async {
    issue('t1');
    await expectLater(connect('c1/s2?ticket=t1'), rejected());

    await expectLater(connect('c1/s1?ticket=t1'), rejected());
  });

  test('an unknown or missing ticket is rejected', () async {
    await expectLater(connect('c1/s1?ticket=nope'), rejected());
    await expectLater(connect('c1/s1?ticket='), rejected());
    await expectLater(connect('c1/s1'), rejected());
  });

  group('changes', () {
    SetRecord record({String clubId = 'c1', String sessionId = 's1'}) =>
        SetRecord(
          id: 'r1',
          clubId: clubId,
          sessionId: sessionId,
          athleteId: 'ari',
          exerciseId: 'sq',
          exerciseName: 'Sentadilla',
          blockIndex: 0,
          prescriptionIndex: 0,
          setIndex: 0,
          kg: 72,
          workFactor: 90,
          pctPlan: 80,
          pctReal: 72,
          sequence: 7,
          writtenBy: 'u1',
          auditoria: Auditoria.nueva('u1', ahora: issuedAt),
        );

    /// Waits for the server to have the socket subscribed: the upgrade answers before its callback runs.
    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 50));

    Future<Map<String, dynamic>> next(StreamIterator<dynamic> socket) async {
      expect(
        await socket.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      return jsonDecode(socket.current as String) as Map<String, dynamic>;
    }

    test('a change reaches every connection of that session', () async {
      issue('t1', canSeeFactors: true);
      issue('t2', canSeeFactors: true);
      final one = await connect('c1/s1?ticket=t1');
      final two = await connect('c1/s1?ticket=t2');
      addTearDown(one.close);
      addTearDown(two.close);
      final fromOne = StreamIterator<dynamic>(one);
      final fromTwo = StreamIterator<dynamic>(two);
      await settle();

      broadcast.publish(SessionChange.ofRecord(7, record()));

      for (final socket in [fromOne, fromTwo]) {
        final change = SessionChange.fromJson(await next(socket));
        expect(change.sequence, 7);
        expect(change.record!.kg, 72);
      }
    });

    test('a change of another session or club does not arrive', () async {
      issue('t1');
      final socket = await connect('c1/s1?ticket=t1');
      addTearDown(socket.close);
      final received = StreamIterator<dynamic>(socket);
      await settle();

      broadcast
        ..publish(SessionChange.ofRecord(1, record(sessionId: 's2')))
        ..publish(SessionChange.ofRecord(2, record(clubId: 'c2')))
        ..publish(SessionChange.ofRecord(3, record()));

      expect((await next(received))['secuencia'], 3);
    });

    test('without permission the factor and the real percent stay out', () async {
      issue('t1');
      final socket = await connect('c1/s1?ticket=t1');
      addTearDown(socket.close);
      final received = StreamIterator<dynamic>(socket);
      await settle();

      broadcast.publish(SessionChange.ofRecord(7, record()));

      final sent = (await next(received))['registro'] as Map<String, dynamic>;
      expect(sent, isNot(contains('factor')));
      expect(sent, isNot(contains('pctReal')));
      expect(sent['pctPlan'], 80);
    });

    test('with permission they travel', () async {
      issue('t1', canSeeFactors: true);
      final socket = await connect('c1/s1?ticket=t1');
      addTearDown(socket.close);
      final received = StreamIterator<dynamic>(socket);
      await settle();

      broadcast.publish(SessionChange.ofRecord(7, record()));

      final sent = (await next(received))['registro'] as Map<String, dynamic>;
      expect([sent['factor'], sent['pctReal']], [90, 72]);
    });

    test('a closed connection stops listening', () async {
      issue('t1');
      final socket = await connect('c1/s1?ticket=t1');
      final closed = socket.drain<void>();
      await settle();

      await socket.close(WebSocketStatus.normalClosure);
      await closed.timeout(const Duration(seconds: 5));
      await settle();

      expect(
        () => broadcast.publish(SessionChange.ofRecord(1, record())),
        returnsNormally,
      );
    });
  });

  group('the access token never opens the channel', () {
    final accessToken = AccessTokenCodec('x' * 32)
        .issue(userId: 'u1', sessionId: 'login-1', now: issuedAt)
        .token;

    test('not as the ticket', () async {
      await expectLater(connect('c1/s1?ticket=$accessToken'), rejected());
    });

    test('not in another query parameter', () async {
      await expectLater(connect('c1/s1?token=$accessToken'), rejected());
      await expectLater(connect('c1/s1?access_token=$accessToken'), rejected());
    });

    test('not in the Authorization header', () async {
      await expectLater(
        WebSocket.connect(
          'ws://localhost:${server.port}/c1/s1',
          headers: {'Authorization': 'Bearer $accessToken'},
        ),
        rejected(),
      );
    });
  });

  group('LiveTickets', () {
    test('saving drops the tickets that already expired', () {
      issue('old');

      tickets.save(
        'new',
        LiveTicket(
          clubId: 'c1',
          sessionId: 's1',
          userId: 'u1',
          expiresAt: issuedAt.add(liveTicketLifetime * 3),
        ),
        now: issuedAt.add(liveTicketLifetime * 2),
      );

      expect(tickets.take('old'), isNull);
      expect(tickets.take('new'), isNotNull);
    });

    test('take returns a ticket only once', () {
      issue('t1');

      expect(tickets.take('t1'), isNotNull);
      expect(tickets.take('t1'), isNull);
    });
  });
}
