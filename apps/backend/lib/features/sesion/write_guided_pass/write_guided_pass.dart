import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/sesion/live_broadcast.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'write_guided_pass_store.dart';

/// `POST /clubes/{clubId}/sesiones/{sesionId}/pasada` body a `GuidedPassAction` → 200 with the `Session`, whose
/// `pasadaGuiada` is the pass after it (E7.26). Needs [Accion.registrar]. A coach writes on any session of the club,
/// an athlete only on one they are present in, as with the note.
///
/// The action carries the version of the pass the device read, but it is applied over the pass as it is now
/// (`applyGuidedAction`): a write that lost a race against another device does what still makes sense, and nothing if
/// nothing does (finishing a block that already closed). A change is published over the live channel as a change of
/// the session; a write that changes nothing is not a change, so retrying it is harmless. Writes of one session go one
/// at a time. 400 if the body is malformed, 403 if the user cannot write on it, 404 if the session is not in the club.
/// [store], [broadcast] and [now] are for tests.
Future<Response> writeGuidedPassEndpoint(
  RequestContext context,
  String sessionId, {
  WriteGuidedPassStore? store,
  LiveBroadcast? broadcast,
  DateTime Function()? now,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.registrar);
  final body = await leerCuerpoJson(context.request);
  final session = await WriteGuidedPass(
    store ?? MongoWriteGuidedPassStore(context.read<Db>()),
    broadcast ?? context.read<LiveBroadcast>(),
    now: now,
  )(club, sessionId, body);
  return Response.json(body: session.toJson());
}

class WriteGuidedPass {
  WriteGuidedPass(this._store, this._broadcast, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final WriteGuidedPassStore _store;
  final LiveBroadcast _broadcast;
  final DateTime Function() _now;

  Future<Session> call(ClubContext club, String sessionId, Json body) async {
    final GuidedPassAction action;
    try {
      action = GuidedPassAction.fromJson(body);
    } on FormatException catch (e) {
      throw ErrorDeSolicitud(e.message);
    } on Object {
      throw const ErrorDeSolicitud('La acción de la pasada no es válida.');
    }
    final session = await _store.session(club.clubId, sessionId);
    if (session == null) {
      throw const ErrorDeSolicitud.noEncontrado('Sesión no encontrada.');
    }
    if (!club.can(Accion.planificar)) {
      final own = await _store.athleteIdOfUser(club.clubId, club.userId);
      if (own == null || !session.presentAthleteIds.contains(own)) {
        throw forbiddenRole;
      }
    }
    return _broadcast.inOrder(sessionId, () async {
      final current = await _store.session(club.clubId, sessionId);
      if (current == null) {
        throw const ErrorDeSolicitud.noEncontrado('Sesión no encontrada.');
      }
      final next = applyGuidedAction(current.guidedPass, action);
      if (next == null || identical(next, current.guidedPass)) return current;
      final stored = await _store.setPass(
        club.clubId,
        sessionId,
        next,
        sequence: await _store.nextSequence(club.clubId, sessionId),
        userId: club.userId,
        at: _now(),
      );
      _broadcast.publish(
        SessionChange.ofSession(stored.lastSessionChange, stored),
      );
      return stored;
    });
  }
}
