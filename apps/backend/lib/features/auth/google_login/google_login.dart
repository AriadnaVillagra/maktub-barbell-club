import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import '../google_id_token.dart';
import '../start_session/start_session.dart';
import '../start_session/start_session_store.dart';
import '../tokens.dart';
import 'google_login_store.dart';

/// `POST /auth/google` with `{"idToken": "<Google ID token>", "device": "<optional label>"}` → an
/// [IssuedSession].
///
/// - 401 if the ID token is not acceptable (bad signature, expired, wrong audience, email not verified…).
/// - 403 if the email has no account, or the account is linked to another Google account. Not 401,
///   because the app treats 401 as "renew the token" (F1, "Identidad"). Chosen in E1.7.
Future<Response> googleLoginEndpoint(RequestContext context) async {
  final body = await leerCuerpoJson(context.request);
  final idToken = body['idToken'];
  if (idToken is! String || idToken.isEmpty) throw const ErrorDeSolicitud('Falta el ID token de Google.');
  final device = body['device'];

  final codec = context.read<AccessTokenCodec>();
  final login = GoogleLogin(
    MongoGoogleLoginStore(context.read<Db>()),
    context.read<GoogleIdTokenVerifier>().verify,
    StartSession(MongoStartSessionStore(context.read<Db>()), codec),
  );
  final issued = await login(idToken: idToken, device: device is String && device.isNotEmpty ? device : null);
  return Response.json(body: issued.toJson());
}

/// Checks a Google ID token; the injectable form of [GoogleIdTokenVerifier.verify].
typedef VerifyGoogleIdToken = Future<GoogleIdentity> Function(String idToken);

const invalidGoogleToken = ErrorDeSolicitud('No se pudo verificar el ingreso con Google.', estado: HttpStatus.unauthorized);

const unknownAccount = ErrorDeSolicitud(
  'Este email no tiene una cuenta en Maktub. Pedile acceso a tu coach.',
  estado: HttpStatus.forbidden,
);

const otherGoogleAccount = ErrorDeSolicitud(
  'Esta cuenta ya está vinculada a otra cuenta de Google.',
  estado: HttpStatus.forbidden,
);

/// Logs in with Google: the email identifies the user (F1, "Identidad"), only users created by the
/// alta script can log in (no sign-up here), and the Google `sub` is linked on the first login.
///
/// Once linked, a different `sub` for the same email is refused: Google can hand an email over to a
/// new account (e.g. a recreated Workspace user), and `sub` is what stays stable.
class GoogleLogin {
  GoogleLogin(this._store, this._verify, this._startSession);

  final GoogleLoginStore _store;
  final VerifyGoogleIdToken _verify;
  final StartSession _startSession;

  Future<IssuedSession> call({required String idToken, String? device}) async {
    final GoogleIdentity identity;
    try {
      identity = await _verify(idToken);
    } on InvalidGoogleToken {
      throw invalidGoogleToken;
    }

    final email = normalizarEmail(identity.email);
    final user = await _store.findByEmail(email);
    if (user == null) throw unknownAccount;

    if (user.googleSub == null && !await _store.linkGoogleSub(email, identity.sub)) {
      // Another login linked an account in between: accept only if it was this same one.
      final again = await _store.findByEmail(email);
      if (again?.googleSub != identity.sub) throw otherGoogleAccount;
    } else if (user.googleSub != null && user.googleSub != identity.sub) {
      throw otherGoogleAccount;
    }

    return _startSession(userId: user.id, device: device);
  }
}
