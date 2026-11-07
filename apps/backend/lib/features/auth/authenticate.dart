import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/infraestructura/http.dart';

import 'tokens.dart';

/// The user making the request, as proven by a valid access token.
class CurrentUser {
  const CurrentUser({required this.userId, required this.sessionId});

  final String userId;
  final String sessionId;
}

const _notAuthenticated = ErrorDeSolicitud('Necesitás iniciar sesión.', estado: HttpStatus.unauthorized);

/// Requires `Authorization: Bearer <accessToken>` and provides [CurrentUser] to the handlers below.
/// Put it in the `_middleware.dart` of every route group that needs a logged-in user. A 401 tells the
/// app to renew with its refresh token and retry once.
///
/// Only the signature and expiry are checked (no database read): a session revoked on logout keeps
/// working for at most [accessTokenLifetime].
Middleware requireUser({DateTime Function()? now}) => (handler) => (context) {
      final token = bearerToken(context.request.headers);
      final claims = token == null ? null : context.read<AccessTokenCodec>().verify(token, now: (now ?? DateTime.now)());
      if (claims == null) throw _notAuthenticated;
      final user = CurrentUser(userId: claims.userId, sessionId: claims.sessionId);
      return handler(context.provide<CurrentUser>(() => user));
    };
