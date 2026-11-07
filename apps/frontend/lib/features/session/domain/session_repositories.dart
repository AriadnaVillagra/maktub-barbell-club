import 'package:maktub_core/maktub_core.dart';

/// Keeps the tokens of this device between app launches.
abstract interface class TokenStore {
  Future<IssuedSession?> read();
  Future<void> write(IssuedSession session);
  Future<void> clear();
}

/// The auth endpoints of the API. None of them sends the access token.
abstract interface class AuthApi {
  /// `POST /auth/google`. An unknown email fails with the API's own error (403), never [SessionRejected].
  Future<IssuedSession> signInWithGoogle(String idToken, {String? device});

  /// `POST /auth/refresh` with the refresh token in the header. Throws [SessionRejected] when the
  /// API says the session is no longer valid; any other failure (no signal, rate limit, 5xx)
  /// propagates as is and leaves the session alone.
  Future<IssuedSession> refresh(String refreshToken);

  /// `POST /auth/logout` with the refresh token in the header: revokes this device's session.
  Future<void> logout(String refreshToken);
}

/// The API rejected the refresh token: the user has to sign in again.
class SessionRejected implements Exception {
  const SessionRejected([this.message = 'La sesión no es válida.']);

  final String message;

  @override
  String toString() => message;
}
