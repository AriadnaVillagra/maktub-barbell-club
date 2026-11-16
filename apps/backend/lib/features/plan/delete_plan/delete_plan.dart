import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'delete_plan_store.dart';

/// `DELETE /clubes/{clubId}/planes/{planId}` → 204. Deletes the plan and its assignments; its sessions, set records
/// and block times stay for the reports (E8.9). Needs [Accion.deletePlan] (coach or club admin). A plan of another
/// club, or one that does not exist, is 404. [store] is for tests.
Future<Response> deletePlanEndpoint(
  RequestContext context,
  String planId, {
  DeletePlanStore? store,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.deletePlan);
  await DeletePlan(store ?? MongoDeletePlanStore(context.read<Db>()))(club, planId);
  return Response(statusCode: 204);
}

class DeletePlan {
  DeletePlan(this._store);

  final DeletePlanStore _store;

  Future<void> call(ClubContext club, String planId) async {
    if (!await _store.deletePlan(club.clubId, planId)) {
      throw const ErrorDeSolicitud.noEncontrado('Plan no encontrado.');
    }
  }
}
