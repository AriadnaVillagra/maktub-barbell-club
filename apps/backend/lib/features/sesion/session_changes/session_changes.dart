import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/sesion/record_view.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'session_changes_store.dart';

/// `GET /clubes/{clubId}/sesiones/{sesionId}/cambios?desde=N` → 200 `{"secuencia": last, "cambios": [SessionChange]}`:
/// what changed after number N, in order and once each, with its current state: something changed twice comes once,
/// with the last number. Needs [Accion.registrar].
///
/// Who can resync is who can follow the session: a coach, any of the club; an athlete, one of their own group. 400 if
/// `desde` is missing or not an integer from 0, 404 if the session is not in the club or is another group's for an
/// athlete. [store] is for tests.
Future<Response> sessionChangesEndpoint(
  RequestContext context,
  String sessionId, {
  SessionChangesStore? store,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.registrar);
  final since = _parseSince(context.request.uri.queryParameters['desde']);
  final result = await SessionChanges(
    store ?? MongoSessionChangesStore(context.read<Db>()),
  )(club, sessionId, since);
  final seesFactors = canSeeFactors(club);
  return Response.json(
    body: {
      'secuencia': result.last,
      'cambios': [
        for (final change in result.changes)
          changeForViewer(change, seesFactors: seesFactors),
      ],
    },
  );
}

int _parseSince(String? value) {
  final since = value == null ? null : int.tryParse(value);
  if (since == null || since < 0) {
    throw const ErrorDeSolicitud('"desde" debe ser un entero desde 0.');
  }
  return since;
}

class SessionChanges {
  SessionChanges(this._store);

  final SessionChangesStore _store;

  static const _notFound = ErrorDeSolicitud.noEncontrado(
    'Sesión no encontrada.',
  );

  Future<({int last, List<SessionChange> changes})> call(
    ClubContext club,
    String sessionId,
    int since,
  ) async {
    final session = await _store.session(club.clubId, sessionId);
    if (session == null) throw _notFound;
    if (!club.can(Accion.planificar) && !await _isInGroup(club, session)) {
      throw _notFound;
    }
    final records = await _store.recordsAfter(club.clubId, sessionId, since);
    final changes = [
      for (final r in records) SessionChange.ofRecord(r.sequence!, r),
      if (session.lastSessionChange > since)
        SessionChange.ofSession(session.lastSessionChange, session),
    ]..sort((a, b) => a.sequence.compareTo(b.sequence));
    return (last: session.sequence, changes: changes);
  }

  Future<bool> _isInGroup(ClubContext club, Session session) async {
    final own = await _store.athleteIdOfUser(club.clubId, club.userId);
    if (own == null) return false;
    final groupId = await _store.groupIdOfAssignment(
      club.clubId,
      session.assignmentId,
    );
    if (groupId == null) return false;
    return (await _store.groupMemberIds(club.clubId, groupId)).contains(own);
  }
}
