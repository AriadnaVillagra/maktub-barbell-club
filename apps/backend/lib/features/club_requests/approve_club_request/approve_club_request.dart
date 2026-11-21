import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/platform_context/platform_context.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'approve_club_request_store.dart';

/// `POST /plataforma/pedidos-club/{pedidoId}/aprobar` → `{pedido, club}`. Needs [Accion.reviewClubRequests]
/// (platform admin). 404 for an unknown request, 409 for a rejected one. Approving an approved request again
/// is allowed and finishes whatever a failed approval left undone. [store], [now] and [newId] are for tests.
Future<Response> approveClubRequestEndpoint(
  RequestContext context,
  String requestId, {
  ApproveClubRequestStore? store,
  DateTime Function()? now,
  String Function()? newId,
}) async {
  final platform = context.read<PlatformContext>().authorize(Accion.reviewClubRequests);
  final approved = await ApproveClubRequest(
    store ?? MongoApproveClubRequestStore(context.read<Db>()),
    now: now,
    newId: newId,
  )(platform, requestId);
  return Response.json(body: {'pedido': approved.request.toJson(), 'club': approved.club.toJson()});
}

const requestNotFound = ErrorDeSolicitud.noEncontrado('Pedido no encontrado.');

const requestAlreadyRejected = ErrorDeSolicitud('Ese pedido ya fue rechazado.', estado: HttpStatus.conflict);

class ApprovedClub {
  const ApprovedClub({required this.request, required this.club, required this.userId});

  final ClubRequest request;
  final Club club;
  final String userId;
}

/// Approves a club request and sets the requester up like the alta script does (`AltaInicial`): their user
/// (linked to the Google account that sent the request) with a personal club, membership and athlete there, and
/// the new club (`TipoClub.club`) where they are `admin_club`, coach and atleta, with an athlete.
///
/// The new club gets no catalog documents of its own: the default catalog (exercises, categories, timers, muscle
/// groups and patterns) is platform data that every club sees (C1), and a club without equipment uses the
/// standard one. Copying them would show each default item twice and stop later corrections from reaching it.
///
/// The request is marked approved first, in one atomic write that only succeeds while it is pending, so two
/// admins approving at once create one club. Every document after that is inserted only if missing, so a
/// repeated approval completes a partial one and changes nothing in a complete one. An existing user with the
/// email (say, added by a club admin meanwhile) is reused as is.
class ApproveClubRequest {
  ApproveClubRequest(this._store, {DateTime Function()? now, String Function()? newId})
    : _now = now ?? DateTime.now,
      _newId = newId ?? (() => ObjectId().oid);

  final ApproveClubRequestStore _store;
  final DateTime Function() _now;
  final String Function() _newId;

  Future<ApprovedClub> call(PlatformContext platform, String requestId) async {
    var found = await _store.find(requestId);
    if (found == null) throw requestNotFound;
    if (found.request.status == ClubRequestStatus.pending) {
      found = await _store.markApproved(
        requestId,
        clubId: _newId(),
        reviewedBy: platform.userId,
        reviewedAt: _now().toUtc(),
      );
      if (found == null) throw requestNotFound;
    }
    final request = found.request;
    if (request.status == ClubRequestStatus.rejected) throw requestAlreadyRejected;
    final clubId = request.createdClubId!;

    final now = _now().toUtc();
    final user = await _store.insertUserIfMissing(
      Usuario(
        id: _newId(),
        email: request.email,
        nombre: request.requesterName,
        emailVerificado: true,
        clubPersonalId: _newId(),
        metodos: const {MetodoIngreso.google},
      ),
      googleSub: found.googleSub,
      auditoria: Auditoria.nueva(platform.userId, ahora: now),
    );
    // Like the alta script, the requester is the author of what is theirs.
    final audit = Auditoria.nueva(user.id, ahora: now);

    await _store.ensureClub(Club(id: user.clubPersonalId, nombre: user.nombre, tipo: TipoClub.personal, auditoria: audit));
    await _memberAndAthlete(user, user.clubPersonalId, const {Rol.coach, Rol.atleta}, audit, now);

    final club = Club(id: clubId, nombre: request.clubName, tipo: TipoClub.club, auditoria: audit);
    await _store.ensureClub(club);
    await _memberAndAthlete(user, clubId, const {Rol.adminClub, Rol.coach, Rol.atleta}, audit, now);

    return ApprovedClub(request: request, club: club, userId: user.id);
  }

  Future<void> _memberAndAthlete(Usuario user, String clubId, Set<Rol> roles, Auditoria audit, DateTime now) async {
    await _store.ensureMembership(
      Membresia(
        id: _newId(),
        clubId: clubId,
        usuarioId: user.id,
        roles: roles,
        estado: EstadoMembresia.activa,
        desde: now,
        auditoria: audit,
      ),
    );
    await _store.ensureAthlete(
      Atleta(id: _newId(), clubId: clubId, usuarioId: user.id, nombreVisible: user.nombre, auditoria: audit),
    );
  }
}
