import 'dart:io';

import 'package:maktub_backend/features/auth/google_id_token.dart';
import 'package:maktub_backend/features/auth/google_login/google_login.dart';
import 'package:maktub_backend/features/auth/google_login/google_login_store.dart';
import 'package:maktub_backend/features/auth/start_session/start_session.dart';
import 'package:maktub_backend/features/auth/start_session/start_session_store.dart';
import 'package:maktub_backend/features/auth/tokens.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:test/test.dart';

class _FakeUsers implements GoogleLoginStore {
  /// email → user row.
  final rows = <String, Map<String, String?>>{};

  /// Simulates another login linking an account between our read and our write.
  String? linkedConcurrently;

  @override
  Future<GoogleLoginUser?> findByEmail(String email) async {
    final r = rows[email];
    return r == null ? null : (id: r['id']!, googleSub: r['googleSub']);
  }

  @override
  Future<bool> linkGoogleSub(String email, String sub) async {
    final r = rows[email];
    if (linkedConcurrently != null) r?['googleSub'] = linkedConcurrently;
    if (r == null || r['googleSub'] != null) return false;
    r['googleSub'] = sub;
    return true;
  }
}

class _FakeSessions implements StartSessionStore {
  final userIds = <String>[];

  @override
  Future<void> insert({
    required String id,
    required String userId,
    required String refreshHash,
    required String? device,
    required DateTime createdAt,
    required DateTime expiresAt,
  }) async =>
      userIds.add(userId);
}

/// Accepts tokens of the form `ok:<sub>:<email>`; anything else is rejected like a bad signature.
Future<GoogleIdentity> _fakeVerify(String token) async {
  final parts = token.split(':');
  if (parts.length == 3 && parts[0] == 'ok') return GoogleIdentity(sub: parts[1], email: parts[2]);
  if (token == 'unverified') throw const InvalidGoogleToken(GoogleTokenRejection.emailNotVerified);
  throw const InvalidGoogleToken(GoogleTokenRejection.invalidSignature);
}

void main() {
  late _FakeUsers users;
  late _FakeSessions sessions;
  late AccessTokenCodec codec;
  late GoogleLogin login;
  final now = DateTime.utc(2026, 11, 7, 10);

  setUp(() {
    users = _FakeUsers()..rows['ari@example.com'] = {'id': 'u-ari', 'googleSub': null};
    sessions = _FakeSessions();
    codec = AccessTokenCodec('x' * 40);
    login = GoogleLogin(users, _fakeVerify, StartSession(sessions, codec, now: () => now));
  });

  Matcher rejectedWith(int status) => throwsA(isA<ErrorDeSolicitud>().having((e) => e.estado, 'estado', status));

  test('a valid token of a registered email returns a session and links the sub on first login', () async {
    final issued = await login(idToken: 'ok:sub-1:ari@example.com');

    expect(codec.verify(issued.accessToken, now: now)!.userId, 'u-ari');
    expect(RefreshToken.parse(issued.refreshToken), isNotNull);
    expect(users.rows['ari@example.com']!['googleSub'], 'sub-1');
    expect(sessions.userIds, ['u-ari']);
  });

  test('the email is compared normalized', () async {
    final issued = await login(idToken: 'ok:sub-1: Ari@Example.COM ');

    expect(codec.verify(issued.accessToken, now: now)!.userId, 'u-ari');
  });

  test('later logins with the same Google account keep working', () async {
    await login(idToken: 'ok:sub-1:ari@example.com');
    await login(idToken: 'ok:sub-1:ari@example.com');

    expect(sessions.userIds, ['u-ari', 'u-ari']);
  });

  test('an email without an account is refused with 403 (not 401) and nothing is created', () async {
    await expectLater(login(idToken: 'ok:sub-9:nadie@example.com'), rejectedWith(HttpStatus.forbidden));

    expect(users.rows.keys, ['ari@example.com']);
    expect(sessions.userIds, isEmpty);
  });

  test('an invalid token or one with an unverified email is refused with 401 without a session', () async {
    await expectLater(login(idToken: 'garbage'), rejectedWith(HttpStatus.unauthorized));
    await expectLater(login(idToken: 'unverified'), rejectedWith(HttpStatus.unauthorized));

    expect(sessions.userIds, isEmpty);
    expect(users.rows['ari@example.com']!['googleSub'], isNull);
  });

  test('a different Google account for an already linked email is refused', () async {
    await login(idToken: 'ok:sub-1:ari@example.com');

    await expectLater(login(idToken: 'ok:sub-2:ari@example.com'), rejectedWith(HttpStatus.forbidden));
    expect(users.rows['ari@example.com']!['googleSub'], 'sub-1');
    expect(sessions.userIds, ['u-ari']);
  });

  test('two first logins racing: the same account wins, a different one is refused', () async {
    users.linkedConcurrently = 'sub-1';
    final issued = await login(idToken: 'ok:sub-1:ari@example.com');
    expect(codec.verify(issued.accessToken, now: now)!.userId, 'u-ari');

    users.rows['ari@example.com']!['googleSub'] = null;
    await expectLater(login(idToken: 'ok:sub-2:ari@example.com'), rejectedWith(HttpStatus.forbidden));
  });
}
