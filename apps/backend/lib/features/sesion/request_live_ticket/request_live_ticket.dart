import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/auth/tokens.dart';
import 'package:maktub_backend/features/sesion/live_tickets.dart';
import 'package:maktub_backend/features/sesion/record_view.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'request_live_ticket_store.dart';

/// `POST /clubes/{clubId}/sesiones/{sesionId}/ticket` → 200 `{ticket, expiresAt}`: a ticket to open the session's
/// live channel, valid once and for [liveTicketLifetime]. Needs [Accion.registrar] and the access token in the
/// `Authorization` header, like any route of the club.
///
/// Who can follow a session is who can open it: a coach, any of the club; an athlete, one of their own group.
/// 404 if the session is not in the club or is another group's for an athlete. [store], [newTicket] and [now] are
/// for tests.
Future<Response> requestLiveTicketEndpoint(
  RequestContext context,
  String sessionId, {
  RequestLiveTicketStore? store,
  String Function()? newTicket,
  DateTime Function()? now,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.registrar);
  final issued = await RequestLiveTicket(
    store ??
        MongoRequestLiveTicketStore(
          context.read<Db>(),
          context.read<LiveTickets>(),
        ),
    newTicket: newTicket,
    now: now,
  )(club, sessionId);
  return Response.json(
    body: {
      'ticket': issued.value,
      'expiresAt': issued.ticket.expiresAt.toUtc().toIso8601String(),
    },
  );
}

class RequestLiveTicket {
  RequestLiveTicket(
    this._store, {
    String Function()? newTicket,
    DateTime Function()? now,
  }) : _newTicket = newTicket ?? randomToken,
       _now = now ?? DateTime.now;

  final RequestLiveTicketStore _store;
  final String Function() _newTicket;
  final DateTime Function() _now;

  static const _notFound = ErrorDeSolicitud.noEncontrado(
    'Sesión no encontrada.',
  );

  Future<({String value, LiveTicket ticket})> call(
    ClubContext club,
    String sessionId,
  ) async {
    final session = await _store.session(club.clubId, sessionId);
    if (session == null) throw _notFound;
    if (!club.can(Accion.planificar) && !await _isInGroup(club, session)) {
      throw _notFound;
    }

    final now = _now().toUtc();
    final value = _newTicket();
    final ticket = LiveTicket(
      clubId: club.clubId,
      sessionId: session.id,
      userId: club.userId,
      expiresAt: now.add(liveTicketLifetime),
      canSeeFactors: canSeeFactors(club),
    );
    _store.saveTicket(value, ticket, now: now);
    return (value: value, ticket: ticket);
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
