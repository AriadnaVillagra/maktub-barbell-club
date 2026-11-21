import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/platform_context/platform_context.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'reject_club_request_store.dart';

/// `POST /plataforma/pedidos-club/{pedidoId}/rechazar` → `{pedido}`. Needs [Accion.reviewClubRequests] (platform
/// admin). 404 for an unknown request, 409 for an approved one; rejecting a rejected one again changes nothing.
/// The requester sees "Tu pedido no fue aprobado" on their next sign-in and may request again.
Future<Response> rejectClubRequestEndpoint(
  RequestContext context,
  String requestId, {
  RejectClubRequestStore? store,
  DateTime Function()? now,
}) async {
  final platform = context.read<PlatformContext>().authorize(Accion.reviewClubRequests);
  final request = await RejectClubRequest(
    store ?? MongoRejectClubRequestStore(context.read<Db>()),
    now: now,
  )(platform, requestId);
  return Response.json(body: {'pedido': request.toJson()});
}

const requestNotFound = ErrorDeSolicitud.noEncontrado('Pedido no encontrado.');

const requestAlreadyApproved = ErrorDeSolicitud('Ese pedido ya fue aprobado.', estado: HttpStatus.conflict);

class RejectClubRequest {
  RejectClubRequest(this._store, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final RejectClubRequestStore _store;
  final DateTime Function() _now;

  Future<ClubRequest> call(PlatformContext platform, String requestId) async {
    final request = await _store.markRejected(requestId, reviewedBy: platform.userId, reviewedAt: _now().toUtc());
    if (request == null) throw requestNotFound;
    if (request.status == ClubRequestStatus.approved) throw requestAlreadyApproved;
    return request;
  }
}
