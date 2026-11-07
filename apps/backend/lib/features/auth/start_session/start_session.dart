import 'package:maktub_core/maktub_core.dart';

import '../tokens.dart';
import 'start_session_store.dart';

/// Opens a login session for a user whose identity was already checked (password or Google).
/// There is no endpoint of its own: the login slices of F1 (tasks 3 and 4) call it.
class StartSession {
  StartSession(this._store, this._codec, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final StartSessionStore _store;
  final AccessTokenCodec _codec;
  final DateTime Function() _now;

  /// [device] is a free label sent by the app (e.g. "Safari en iPhone"), to list sessions later.
  Future<IssuedSession> call({required String userId, String? device}) async {
    final now = _now().toUtc();
    final refresh = RefreshToken.generate(newId());
    await _store.insert(
      id: refresh.sessionId,
      userId: userId,
      refreshHash: refresh.hash,
      device: device,
      createdAt: now,
      expiresAt: now.add(refreshTokenLifetime),
    );
    final access = _codec.issue(userId: userId, sessionId: refresh.sessionId, now: now);
    return IssuedSession(accessToken: access.token, accessTokenExpiresAt: access.expiresAt, refreshToken: '$refresh');
  }
}
