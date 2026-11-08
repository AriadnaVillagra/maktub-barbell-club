import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'leer_store.dart';

/// `GET /clubes/{clubId}/planes/{planId}` → the whole plan (week models, assignment, days, blocks,
/// prescriptions and sets). Needs [Accion.planificar] (the coach). A plan of another club, or one that does
/// not exist, is 404. [store] is for tests.
Future<Response> readPlanEndpoint(
  RequestContext context,
  String planId, {
  ReadPlanStore? store,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.planificar);
  final plan = await ReadPlan(store ?? MongoReadPlanStore(context.read<Db>()))(
    club,
    planId,
  );
  return Response.json(body: plan.toJson());
}

class ReadPlan {
  ReadPlan(this._store);

  final ReadPlanStore _store;

  Future<Plan> call(ClubContext club, String planId) async {
    final plan = await _store.plan(club.clubId, planId);
    if (plan == null) {
      throw const ErrorDeSolicitud.noEncontrado('Plan no encontrado.');
    }
    return plan;
  }
}
