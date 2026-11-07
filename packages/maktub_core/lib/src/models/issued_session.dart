import '../modelos/json.dart';

/// What the API returns when it starts or renews a login session (F1, "Identidad").
///
/// The app keeps both tokens itself (never in cookies: the app and the API live on different sites)
/// and sends them in the `Authorization` header: the access token on every request, the refresh token
/// only to `/auth/refresh` and `/auth/logout`. The refresh token rotates on every use, so the app must
/// replace it with the new one each time and never send two refreshes at once.
class IssuedSession {
  const IssuedSession({required this.accessToken, required this.accessTokenExpiresAt, required this.refreshToken});

  final String accessToken;

  /// UTC instant. The app can renew a little before it, or when a request answers 401.
  final DateTime accessTokenExpiresAt;
  final String refreshToken;

  factory IssuedSession.fromJson(Json j) => IssuedSession(
        accessToken: '${j['accessToken']}',
        accessTokenExpiresAt: DateTime.parse('${j['accessTokenExpiresAt']}').toUtc(),
        refreshToken: '${j['refreshToken']}',
      );

  Json toJson() => {
        'accessToken': accessToken,
        'accessTokenExpiresAt': accessTokenExpiresAt.toUtc().toIso8601String(),
        'refreshToken': refreshToken,
      };
}
