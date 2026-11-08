import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'listar_store.dart';

/// `GET /clubes/{clubId}/asignaciones[?grupoId=...]` → the club's assignments, each as `Assignment.toJson()`
/// (`id`, `clubId`, `planId`, `grupoId`, `fechaInicio`, `estado`, `fechaFin` when ended, `auditoria`), the active
/// ones and the ended ones, newest `fechaInicio` first (ties broken by id). With `grupoId`, only that group's.
/// Needs [Accion.verCatalogoYPlanes]: the coach and the athletes of the club. [store] is for tests.
Future<Response> listAssignmentsEndpoint(
  RequestContext context, {
  ListAssignmentsStore? store,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.verCatalogoYPlanes);
  final groupId = context.request.uri.queryParameters['grupoId']?.trim();
  final assignments = await ListAssignments(
    store ?? MongoListAssignmentsStore(context.read<Db>()),
  )(club, groupId: groupId == null || groupId.isEmpty ? null : groupId);
  return Response.json(body: assignments);
}

class ListAssignments {
  ListAssignments(this._store);

  final ListAssignmentsStore _store;

  Future<List<Json>> call(ClubContext club, {String? groupId}) async {
    final all = [...await _store.assignments(club.clubId, groupId: groupId)]
      ..sort((a, b) {
        final byDate = b.startDate.compareTo(a.startDate);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });
    return [for (final a in all) a.toJson()];
  }
}
