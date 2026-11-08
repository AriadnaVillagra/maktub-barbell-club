import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/plan/plan_problem_json.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'publicar_store.dart';

/// `POST /clubes/{clubId}/planes/{planId}/publicar` (no body) → 200 with the plan, whose `publicado` is now a
/// copy of the saved week models and assignment with `publicadoEn` (UTC instant) and `publicadoPor` (the caller).
/// Athletes only ever see that copy; saving a plan never changes it. Publishing twice in a row just refreshes
/// the date. Needs [Accion.planificar] (the coach). 404 if the plan does not exist in the club.
///
/// The saved plan must have no problem at all (`validatePlan`, not only the ones that block saving): otherwise
/// it is 422 with `problemas` in the same shape as saving, nothing is written and the previous published
/// version stays. The copy is one document write; if the plan was saved between the read and the write it is
/// 409 and nothing is written (publish again). [store] and [now] are for tests.
Future<Response> publishPlanEndpoint(
  RequestContext context,
  String planId, {
  PublishPlanStore? store,
  DateTime Function()? now,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.planificar);
  final plan = await PublishPlan(
    store ?? MongoPublishPlanStore(context.read<Db>()),
    now: now,
  )(club, planId);
  return Response.json(body: plan.toJson());
}

class PublishPlan {
  PublishPlan(this._store, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final PublishPlanStore _store;
  final DateTime Function() _now;

  Future<Plan> call(ClubContext club, String planId) async {
    final plan = await _store.plan(club.clubId, planId);
    if (plan == null) {
      throw const ErrorDeSolicitud.noEncontrado('Plan no encontrado.');
    }

    final exercises = await _store.exercises(club.clubId);
    final problems = validatePlan(plan, exerciseById: (id) => exercises[id]);
    if (problems.isNotEmpty) {
      throw ErrorDeSolicitud(
        'El plan tiene ${problems.length} problema(s); no se publicó.',
        estado: 422,
        extra: {
          'problemas': [for (final p in problems) planProblemJson(p)],
        },
      );
    }

    final copy = PublishedPlan(
      weekModels: plan.weekModels,
      weekAssignment: plan.weekAssignment,
      publishedAt: _now().toUtc(),
      publishedBy: club.userId,
    );
    final written = await _store.publish(
      club.clubId,
      plan.id,
      copy,
      savedAt: plan.auditoria.modificadoEn,
    );
    if (!written) {
      throw const ErrorDeSolicitud(
        'El plan cambió mientras se publicaba; volvé a intentar.',
        estado: 409,
      );
    }
    return Plan(
      id: plan.id,
      clubId: plan.clubId,
      name: plan.name,
      type: plan.type,
      weekModels: plan.weekModels,
      weekAssignment: plan.weekAssignment,
      published: copy,
      auditoria: plan.auditoria,
    );
  }
}
