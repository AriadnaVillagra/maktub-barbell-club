import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/plan/plan_problem_json.dart';
import 'package:maktub_backend/features/plan/read_only_plan.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'publicar_store.dart';

/// `POST /clubes/{clubId}/planes/{planId}/publicar` (no body) → 200 with the plan, whose `publicado` is now a
/// copy of the saved week models and assignment with `publicadoEn` (UTC instant) and `publicadoPor` (the caller).
/// Athletes only ever see that copy; saving a plan never changes it. Publishing twice in a row just refreshes
/// the date. Needs [Accion.planificar] (the coach). 404 if the plan does not exist in the club or the caller
/// cannot see it; 403 if they see it but cannot change it ([PlanAccess.edit]).
///
/// The saved plan must have no problem at all (`validatePlan`, not only the ones that block saving; a
/// [PlanType.history] plan is not asked for % or reps, [historyPlanAccepts]). It is validated for who the plan is
/// for (`planAthleteIds` of its assignments): for more than one, each set in kilos needs every athlete's kilos
/// (`setWithoutAthleteKg`, with `atleta`). Otherwise
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

/// What a history-mode publish lets through: the old spreadsheet never recorded the % or, for a few sets, the reps
/// of what was done, and a plan rebuilt from that record cannot have them. A [PlanType.history] plan gets the same
/// through the endpoint, because `validatePlan` does not report them for it ([historyPlanAccepts]).
const historyPublishAccepts = historyPlanAccepts;

class PublishPlan {
  PublishPlan(this._store, {DateTime Function()? now, this._history = false, this._askAthleteKg = true})
    : _now = now ?? DateTime.now;

  final PublishPlanStore _store;
  final DateTime Function() _now;

  /// Loading history (the E8 importer): sets without % or reps ([historyPublishAccepts]) do not stop the
  /// publication of any plan; every other problem still does. The endpoint never sets it (a [PlanType.history]
  /// plan already gets that from `validatePlan`).
  final bool _history;

  /// Whether the plan is validated for the athletes of its assignments (kilos per athlete in its sets in kilos).
  /// The E8 importer turns it off: the old spreadsheet never had kilos per athlete.
  final bool _askAthleteKg;

  Future<Plan> call(ClubContext club, String planId) async {
    final plan = await _store.plan(club.clubId, planId);
    final access = plan == null ? null : club.planAccess(plan);
    if (plan == null || !access!.see) {
      throw const ErrorDeSolicitud.noEncontrado('Plan no encontrado.');
    }
    if (!access.edit) throw readOnlyPlan;

    final exercises = await _store.exercises(club.clubId);
    final athleteIds = _askAthleteKg
        ? planAthleteIds(await _store.assignments(club.clubId, plan.id))
        : const <String>[];
    final problems = [
      for (final p in validatePlan(plan, exerciseById: (id) => exercises[id], athleteIds: athleteIds))
        if (!_history || !historyPublishAccepts.contains(p.code)) p,
    ];
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
      past: plan.past,
      visibility: plan.visibility,
      weekModels: plan.weekModels,
      weekAssignment: plan.weekAssignment,
      published: copy,
      auditoria: plan.auditoria,
    );
  }
}
