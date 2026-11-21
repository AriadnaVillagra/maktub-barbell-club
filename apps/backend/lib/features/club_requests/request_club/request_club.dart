import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/auth/google_id_token.dart';
import 'package:maktub_backend/features/auth/google_login/google_login.dart' show VerifyGoogleIdToken, invalidGoogleToken;
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'request_club_store.dart';

/// `POST /auth/pedidos-club` with `{"idToken": "<Google ID token>", "nombreClub", "nombre", "nota"?}` → 201
/// `{pedido}` ([ClubRequest], pending). No session: whoever sends it has no account yet, so the Google ID token
/// proves the email, as in `POST /auth/google`. Rate-limited like it (`routes/auth/_middleware.dart`).
///
/// - 400 for missing or too long names or note (`problemas` lists them);
/// - 401 if the ID token is not acceptable;
/// - 409 if the email already has an account, or already has a request waiting (`codigo: pedido_pendiente`).
///   After a rejection a new request may be sent.
Future<Response> requestClubEndpoint(RequestContext context) async {
  final body = await leerCuerpoJson(context.request);
  final request = await RequestClub(
    MongoRequestClubStore(context.read<Db>()),
    context.read<GoogleIdTokenVerifier>().verify,
  )(body);
  return Response.json(statusCode: HttpStatus.created, body: {'pedido': request.toJson()});
}

const alreadyHasAccount = ErrorDeSolicitud(
  'Este email ya tiene una cuenta en Maktub: ingresá con Google.',
  estado: HttpStatus.conflict,
);

final alreadyRequested = ErrorDeSolicitud(
  'Ya tenés un pedido en revisión.',
  estado: HttpStatus.conflict,
  extra: {'codigo': SignInRefusal.requestPending.cable},
);

/// Stores a pending club request for someone without an account. Nothing else is created: no user, club or
/// membership exists until a platform admin approves it.
class RequestClub {
  RequestClub(this._store, this._verify, {DateTime Function()? now, String Function()? newId})
    : _now = now ?? DateTime.now,
      _newId = newId ?? (() => ObjectId().oid);

  final RequestClubStore _store;
  final VerifyGoogleIdToken _verify;
  final DateTime Function() _now;
  final String Function() _newId;

  Future<ClubRequest> call(Json body) async {
    final idToken = body['idToken'];
    if (idToken is! String || idToken.isEmpty) throw const ErrorDeSolicitud('Falta el ID token de Google.');
    final GoogleIdentity identity;
    try {
      identity = await _verify(idToken);
    } on InvalidGoogleToken {
      throw invalidGoogleToken;
    }

    final clubName = _text(body['nombreClub'], 'nombreClub');
    final requesterName = _text(body['nombre'], 'nombre');
    final note = body['nota'] == null ? '' : _text(body['nota'], 'nota');
    final problems = ClubRequest.problems(clubName: clubName, requesterName: requesterName, note: note);
    if (problems.isNotEmpty) throw ErrorDeSolicitud(problems.first, extra: {'problemas': problems});

    final email = normalizarEmail(identity.email);
    if (await _store.userExists(email)) throw alreadyHasAccount;
    final latest = await _store.latestStatus(email);
    if (latest == ClubRequestStatus.pending || latest == ClubRequestStatus.approved) throw alreadyRequested;

    final request = ClubRequest(
      id: _newId(),
      email: email,
      requesterName: requesterName,
      clubName: clubName,
      note: note.isEmpty ? null : note,
      // There is no user yet: the author is the proven email.
      auditoria: Auditoria.nueva(email, ahora: _now()),
    );
    // The unique index on pending requests settles two requests sent at once.
    if (!await _store.insertPending(request, googleSub: identity.sub)) throw alreadyRequested;
    return request;
  }

  static String _text(Object? raw, String field) {
    if (raw is! String) throw ErrorDeSolicitud('"$field" tiene que ser un texto.');
    return raw.trim();
  }
}
