import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mongo_dart/mongo_dart.dart';

import '../tokens.dart';
import 'end_session_store.dart';

/// `POST /auth/logout` with `Authorization: Bearer <refreshToken>` → 204.
/// Always answers 204, so logging out twice or with a stale token is harmless for the app.
Future<Response> endSessionEndpoint(RequestContext context) async {
  await EndSession(MongoEndSessionStore(context.read<Db>()))(bearerToken(context.request.headers));
  return Response(statusCode: HttpStatus.noContent);
}

/// Logs out one device: revokes its session. The other devices of the same user keep theirs.
/// Needs the current refresh token, not just the session id (which is readable inside access tokens).
class EndSession {
  EndSession(this._store, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final EndSessionStore _store;
  final DateTime Function() _now;

  Future<void> call(String? token) async {
    final presented = token == null ? null : RefreshToken.parse(token);
    if (presented == null) return;
    await _store.revokeIfCurrent(presented.sessionId, presented.hash, _now().toUtc());
  }
}
