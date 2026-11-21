import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/platform_context/platform_context.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'list_club_requests_store.dart';

/// `GET /plataforma/pedidos-club[?estado=pendiente|aprobado|rechazado|todos]` → `{pedidos: [ClubRequest…]}`,
/// oldest first. Without `estado`, the pending ones. Needs [Accion.reviewClubRequests] (platform admin).
Future<Response> listClubRequestsEndpoint(RequestContext context, {ListClubRequestsStore? store}) async {
  context.read<PlatformContext>().authorize(Accion.reviewClubRequests);
  final requests = await ListClubRequests(store ?? MongoListClubRequestsStore(context.read<Db>()))(
    context.request.uri.queryParameters['estado'],
  );
  return Response.json(body: {'pedidos': [for (final r in requests) r.toJson()]});
}

class ListClubRequests {
  ListClubRequests(this._store);

  final ListClubRequestsStore _store;

  Future<List<ClubRequest>> call(String? status) async {
    if (status == 'todos') return _store.list();
    final ClubRequestStatus wanted;
    try {
      wanted = status == null ? ClubRequestStatus.pending : ClubRequestStatus.fromWire(status);
    } on FormatException {
      throw const ErrorDeSolicitud('"estado" tiene que ser pendiente, aprobado, rechazado o todos.');
    }
    return _store.list(status: wanted);
  }
}
