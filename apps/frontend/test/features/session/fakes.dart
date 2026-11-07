import 'dart:async';

import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/session/domain/session_repositories.dart';

IssuedSession issued(int n) => IssuedSession(
      accessToken: 'access-$n',
      accessTokenExpiresAt: DateTime.utc(2026, 11, 7, 12, n),
      refreshToken: 'refresh-$n',
    );

class FakeTokenStore implements TokenStore {
  FakeTokenStore([this.saved]);

  IssuedSession? saved;

  @override
  Future<IssuedSession?> read() async => saved;

  @override
  Future<void> write(IssuedSession session) async => saved = session;

  @override
  Future<void> clear() async => saved = null;
}

/// Each refresh waits on a [Completer] the test completes, so tests can line requests up behind it.
class FakeAuthApi implements AuthApi {
  final signInCalls = <String>[];
  final refreshCalls = <String>[];
  final logoutCalls = <String>[];
  final pendingRefreshes = <Completer<IssuedSession>>[];
  Object? logoutError;
  IssuedSession signInResult = issued(1);
  Object? signInError;

  @override
  Future<IssuedSession> signInWithGoogle(String idToken, {String? device}) async {
    signInCalls.add(idToken);
    if (signInError != null) throw signInError!;
    return signInResult;
  }

  @override
  Future<IssuedSession> refresh(String refreshToken) {
    refreshCalls.add(refreshToken);
    final completer = Completer<IssuedSession>();
    pendingRefreshes.add(completer);
    return completer.future;
  }

  @override
  Future<void> logout(String refreshToken) async {
    logoutCalls.add(refreshToken);
    if (logoutError != null) throw logoutError!;
  }
}
