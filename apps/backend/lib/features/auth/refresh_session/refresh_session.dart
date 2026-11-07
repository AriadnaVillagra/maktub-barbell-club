import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import '../tokens.dart';
import 'refresh_session_store.dart';

/// `POST /auth/refresh` with `Authorization: Bearer <refreshToken>` → a new [IssuedSession].
Future<Response> refreshSessionEndpoint(RequestContext context) async {
  final refresh = RefreshSession(MongoRefreshSessionStore(context.read<Db>()), context.read<AccessTokenCodec>());
  final issued = await refresh(bearerToken(context.request.headers));
  return Response.json(body: issued.toJson());
}

const invalidSession = ErrorDeSolicitud('La sesión no es válida. Volvé a iniciar sesión.', estado: HttpStatus.unauthorized);

/// Renews a session and rotates its refresh token.
///
/// Presenting a refresh token that is not the current one (already rotated, or two refreshes racing)
/// is treated as theft: the whole session of that device is revoked and the app has to log in again.
class RefreshSession {
  RefreshSession(this._store, this._codec, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final RefreshSessionStore _store;
  final AccessTokenCodec _codec;
  final DateTime Function() _now;

  Future<IssuedSession> call(String? token) async {
    final presented = token == null ? null : RefreshToken.parse(token);
    if (presented == null) throw invalidSession;

    final now = _now().toUtc();
    final session = await _store.find(presented.sessionId);
    if (session == null || session.revoked || !now.isBefore(session.expiresAt)) throw invalidSession;

    if (!sameText(presented.hash, session.refreshHash)) {
      await _store.revoke(presented.sessionId, now);
      throw invalidSession;
    }

    final next = RefreshToken.generate(presented.sessionId);
    final rotated = await _store.rotate(
      presented.sessionId,
      expectedHash: session.refreshHash,
      newHash: next.hash,
      expiresAt: now.add(refreshTokenLifetime),
      now: now,
    );
    if (!rotated) {
      await _store.revoke(presented.sessionId, now);
      throw invalidSession;
    }

    final access = _codec.issue(userId: session.userId, sessionId: presented.sessionId, now: now);
    return IssuedSession(accessToken: access.token, accessTokenExpiresAt: access.expiresAt, refreshToken: '$next');
  }
}
