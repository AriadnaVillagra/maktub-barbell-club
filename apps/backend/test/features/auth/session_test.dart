import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/auth/authenticate.dart';
import 'package:maktub_backend/features/auth/end_session/end_session.dart';
import 'package:maktub_backend/features/auth/end_session/end_session_store.dart';
import 'package:maktub_backend/features/auth/refresh_session/refresh_session.dart';
import 'package:maktub_backend/features/auth/refresh_session/refresh_session_store.dart';
import 'package:maktub_backend/features/auth/start_session/start_session.dart';
import 'package:maktub_backend/features/auth/start_session/start_session_store.dart';
import 'package:maktub_backend/features/auth/tokens.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

/// One in-memory table that implements every slice's store, like the Mongo collection would.
class _FakeSessions implements StartSessionStore, RefreshSessionStore, EndSessionStore {
  final rows = <String, Map<String, Object?>>{};

  @override
  Future<void> insert({
    required String id,
    required String userId,
    required String refreshHash,
    required String? device,
    required DateTime createdAt,
    required DateTime expiresAt,
  }) async {
    rows[id] = {'userId': userId, 'refreshHash': refreshHash, 'previousHashes': <String>[], 'device': device, 'expiresAt': expiresAt, 'revokedAt': null};
  }

  @override
  Future<StoredSession?> find(String sessionId) async {
    final r = rows[sessionId];
    if (r == null) return null;
    return (
      userId: r['userId']! as String,
      refreshHash: r['refreshHash']! as String,
      previousHashes: (r['previousHashes']! as List).cast<String>(),
      expiresAt: r['expiresAt']! as DateTime,
      revoked: r['revokedAt'] != null,
    );
  }

  @override
  Future<bool> rotate(String sessionId, {required String expectedHash, required String newHash, required DateTime expiresAt, required DateTime now}) async {
    final r = rows[sessionId];
    if (r == null || r['refreshHash'] != expectedHash || r['revokedAt'] != null) return false;
    (r['previousHashes']! as List).add(expectedHash);
    r
      ..['refreshHash'] = newHash
      ..['expiresAt'] = expiresAt;
    return true;
  }

  @override
  Future<void> revoke(String sessionId, DateTime now) async {
    rows[sessionId]?['revokedAt'] ??= now;
  }

  @override
  Future<void> revokeIfCurrent(String sessionId, String refreshHash, DateTime now) async {
    final r = rows[sessionId];
    if (r != null && r['refreshHash'] == refreshHash) r['revokedAt'] ??= now;
  }

  bool isRevoked(String sessionId) => rows[sessionId]!['revokedAt'] != null;
}

class _Context extends Mock implements RequestContext {}

final _secret = 'x' * 40;

void main() {
  late _FakeSessions sessions;
  late AccessTokenCodec codec;
  late DateTime now;
  late StartSession start;
  late RefreshSession refresh;
  late EndSession end;

  setUp(() {
    sessions = _FakeSessions();
    codec = AccessTokenCodec(_secret);
    now = DateTime.utc(2026, 11, 7, 10);
    start = StartSession(sessions, codec, now: () => now);
    refresh = RefreshSession(sessions, codec, now: () => now);
    end = EndSession(sessions, now: () => now);
  });

  String sessionIdOf(String refreshToken) => RefreshToken.parse(refreshToken)!.sessionId;

  Matcher throwsUnauthorized() =>
      throwsA(isA<ErrorDeSolicitud>().having((e) => e.estado, 'estado', HttpStatus.unauthorized));

  group('access tokens', () {
    test('a token issued now is valid until it expires', () {
      final issued = codec.issue(userId: 'u1', sessionId: 's1', now: now);
      final claims = codec.verify(issued.token, now: now.add(const Duration(minutes: 14)))!;

      expect((claims.userId, claims.sessionId), ('u1', 's1'));
      expect(issued.expiresAt, now.add(accessTokenLifetime));
      expect(codec.verify(issued.token, now: now.add(accessTokenLifetime)), isNull);
    });

    test('a tampered token or one signed with another secret is rejected', () {
      final token = codec.issue(userId: 'u1', sessionId: 's1', now: now).token;
      final parts = token.split('.');
      final otherUser = codec.issue(userId: 'u2', sessionId: 's1', now: now).token.split('.')[1];

      expect(codec.verify('${parts[0]}.$otherUser.${parts[2]}', now: now), isNull);
      expect(AccessTokenCodec('y' * 40).verify(token, now: now), isNull);
      expect(codec.verify('not-a-token', now: now), isNull);
    });

    test('a short secret is refused', () {
      expect(() => AccessTokenCodec('short'), throwsArgumentError);
    });
  });

  group('sessions', () {
    test('starting a session stores only the hash of the refresh token', () async {
      final issued = await start(userId: 'u1', device: 'Safari en iPhone');
      final id = sessionIdOf(issued.refreshToken);

      expect(sessions.rows[id]!['userId'], 'u1');
      expect(sessions.rows[id]!['refreshHash'], isNot(contains(RefreshToken.parse(issued.refreshToken)!.secret)));
      expect(codec.verify(issued.accessToken, now: now)!.sessionId, id);
    });

    test('refreshing rotates the refresh token and keeps the same session', () async {
      final first = await start(userId: 'u1');
      now = now.add(const Duration(days: 1));
      final second = await refresh(first.refreshToken);

      expect(second.refreshToken, isNot(first.refreshToken));
      expect(sessionIdOf(second.refreshToken), sessionIdOf(first.refreshToken));
      expect(codec.verify(second.accessToken, now: now)!.userId, 'u1');
      expect(sessions.rows[sessionIdOf(first.refreshToken)]!['expiresAt'], now.add(refreshTokenLifetime));
    });

    test('reusing a rotated refresh token revokes the session of that device', () async {
      final first = await start(userId: 'u1');
      final second = await refresh(first.refreshToken);

      await expectLater(refresh(first.refreshToken), throwsUnauthorized());
      expect(sessions.isRevoked(sessionIdOf(first.refreshToken)), isTrue);
      await expectLater(refresh(second.refreshToken), throwsUnauthorized());
    });

    test('a secret that was never issued is rejected and the session stays active', () async {
      final issued = await start(userId: 'u1');
      final id = sessionIdOf(issued.refreshToken);

      await expectLater(refresh('$id.never-issued'), throwsUnauthorized());

      expect(sessions.isRevoked(id), isFalse);
      expect((await refresh(issued.refreshToken)).refreshToken, isNotEmpty);
    });

    test('reusing a rotated token does not touch the other devices of the user', () async {
      final phone = await start(userId: 'u1', device: 'phone');
      final laptop = await start(userId: 'u1', device: 'laptop');
      await refresh(phone.refreshToken);

      await expectLater(refresh(phone.refreshToken), throwsUnauthorized());

      expect(sessions.isRevoked(sessionIdOf(phone.refreshToken)), isTrue);
      expect(sessions.isRevoked(sessionIdOf(laptop.refreshToken)), isFalse);
      expect((await refresh(laptop.refreshToken)).refreshToken, isNotEmpty);
    });

    test('an expired, unknown or malformed refresh token is rejected', () async {
      final issued = await start(userId: 'u1');

      await expectLater(refresh(null), throwsUnauthorized());
      await expectLater(refresh('garbage'), throwsUnauthorized());
      await expectLater(refresh('unknown.secret'), throwsUnauthorized());

      now = now.add(refreshTokenLifetime);
      await expectLater(refresh(issued.refreshToken), throwsUnauthorized());
    });

    test('logging out on one device leaves the other devices logged in', () async {
      final phone = await start(userId: 'u1', device: 'phone');
      final laptop = await start(userId: 'u1', device: 'laptop');

      await end(phone.refreshToken);

      await expectLater(refresh(phone.refreshToken), throwsUnauthorized());
      expect((await refresh(laptop.refreshToken)).refreshToken, isNotEmpty);
    });

    test('logging out needs the current refresh token, not just the session id', () async {
      final issued = await start(userId: 'u1');
      final id = sessionIdOf(issued.refreshToken);

      await end('$id.guessed');
      await end(null);

      expect(sessions.isRevoked(id), isFalse);
    });
  });

  group('requireUser', () {
    Future<Response> call(Map<String, String> headers, {DateTime? at}) async {
      final context = _Context();
      when(() => context.request).thenReturn(Request('GET', Uri.parse('http://localhost/x'), headers: headers));
      when(() => context.read<AccessTokenCodec>()).thenReturn(codec);
      when(() => context.provide<CurrentUser>(any())).thenAnswer((inv) {
        final user = (inv.positionalArguments.first as CurrentUser Function())();
        final inner = _Context();
        when(() => inner.read<CurrentUser>()).thenReturn(user);
        return inner;
      });
      Response handler(RequestContext c) => Response(body: c.read<CurrentUser>().userId);
      return manejarErrores()(requireUser(now: () => at ?? now)(handler))(context);
    }

    test('a valid access token reaches the handler with the current user', () async {
      final token = codec.issue(userId: 'u1', sessionId: 's1', now: now).token;
      final response = await call({'authorization': 'Bearer $token'});

      expect(response.statusCode, HttpStatus.ok);
      expect(await response.body(), 'u1');
    });

    test('without a token or with an expired one it answers 401', () async {
      final token = codec.issue(userId: 'u1', sessionId: 's1', now: now).token;

      expect((await call({})).statusCode, HttpStatus.unauthorized);
      expect((await call({'authorization': 'Bearer $token'}, at: now.add(accessTokenLifetime))).statusCode, HttpStatus.unauthorized);
    });
  });
}
