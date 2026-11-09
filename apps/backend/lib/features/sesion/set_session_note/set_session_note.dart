import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/sesion/live_broadcast.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'set_session_note_store.dart';

/// `PUT /clubes/{clubId}/sesiones/{sesionId}/nota` body `{nota}` → 200 with the `Session`. Needs [Accion.registrar].
/// Empty clears the note. A coach writes it on any session of the club, an athlete only on one they are present in.
/// A new note is published as a change of the session; writing the same one again changes nothing. 400 if the body is
/// malformed, 403 if the user cannot write on it, 404 if the session is not in the club. [store], [broadcast] and
/// [now] are for tests.
Future<Response> setSessionNoteEndpoint(
  RequestContext context,
  String sessionId, {
  SetSessionNoteStore? store,
  LiveBroadcast? broadcast,
  DateTime Function()? now,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.registrar);
  final body = await leerCuerpoJson(context.request);
  final session = await SetSessionNote(
    store ?? MongoSetSessionNoteStore(context.read<Db>()),
    broadcast ?? context.read<LiveBroadcast>(),
    now: now,
  )(club, sessionId, body);
  return Response.json(body: session.toJson());
}

class SetSessionNote {
  SetSessionNote(this._store, this._broadcast, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final SetSessionNoteStore _store;
  final LiveBroadcast _broadcast;
  final DateTime Function() _now;

  Future<Session> call(ClubContext club, String sessionId, Json body) async {
    final note = _parseNote(body['nota']);
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
      if (current != null && current.note == note) return current;
      final stored = await _store.setNote(
        club.clubId,
        sessionId,
        note,
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

String? _parseNote(Object? value) {
  if (value is! String) throw const ErrorDeSolicitud('"nota" debe ser texto.');
  if (value.length > maxNoteLength) {
    throw const ErrorDeSolicitud('"nota" es demasiado larga.');
  }
  final note = value.trim();
  return note.isEmpty ? null : note;
}
