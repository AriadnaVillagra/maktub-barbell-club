import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'guardar_store.dart';

/// `PUT /clubes/{clubId}/planes/{planId}` body: the whole plan as `Plan.toJson()` (week models, assignment,
/// days, blocks, prescriptions, sets) → 200 with the saved plan. It replaces the stored plan entirely, in one
/// document write, so a failure leaves the previous plan intact. Saving the same body twice gives the same plan.
///
/// The server sets `id` (the one in the URL), `clubId` (the club's) and the audit (creation is kept from the
/// stored plan; modification is the caller and now): whatever the body says for them is ignored.
/// 404 if the plan does not exist in the club (create it first with `POST`). Needs [Accion.planificar].
///
/// An invalid plan is 422 and nothing is written, with every problem and where it is:
/// `{"error": "...", "problemas": [{"codigo": "setWithoutPct", "modeloSemana": 0, "dia": 1, "bloque": 0,
/// "prescripcion": 2, "serie": 1}, ...]}`. `codigo` is a `PlanProblemCode` name; the location keys are
/// 0-based and only present when the problem is at that level (`semana` is the position in the assignment).
/// [store] and [now] are for tests.
Future<Response> savePlanEndpoint(
  RequestContext context,
  String planId, {
  SavePlanStore? store,
  DateTime Function()? now,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.planificar);
  final body = await leerCuerpoJson(context.request);
  final plan = await SavePlan(
    store ?? MongoSavePlanStore(context.read<Db>()),
    now: now,
  )(club, planId, body);
  return Response.json(body: plan.toJson());
}

class SavePlan {
  SavePlan(this._store, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final SavePlanStore _store;
  final DateTime Function() _now;

  Future<Plan> call(ClubContext club, String planId, Json body) async {
    final stored = await _store.plan(club.clubId, planId);
    if (stored == null) {
      throw const ErrorDeSolicitud.noEncontrado('Plan no encontrado.');
    }

    final Plan plan;
    try {
      plan = Plan.fromJson({
        ...body,
        'id': stored.id,
        'clubId': club.clubId,
        'auditoria': stored.auditoria
            .modificada(club.userId, ahora: _now())
            .toJson(),
      });
    } on FormatException {
      throw const ErrorDeSolicitud('El plan tiene un formato inválido.');
    } on TypeError {
      throw const ErrorDeSolicitud('El plan tiene un formato inválido.');
    }

    final exercises = await _store.exercises(club.clubId);
    final problems = validatePlan(plan, exerciseById: (id) => exercises[id]);
    if (problems.isNotEmpty) {
      throw ErrorDeSolicitud(
        'El plan tiene ${problems.length} problema(s); no se guardó.',
        estado: 422,
        extra: {
          'problemas': [for (final p in problems) _problemJson(p)],
        },
      );
    }

    if (!await _store.replace(plan)) {
      throw const ErrorDeSolicitud.noEncontrado('Plan no encontrado.');
    }
    return plan;
  }
}

Json _problemJson(PlanProblem p) => {
  'codigo': p.code.name,
  if (p.weekModelIndex != null) 'modeloSemana': p.weekModelIndex,
  if (p.assignmentIndex != null) 'semana': p.assignmentIndex,
  if (p.dayIndex != null) 'dia': p.dayIndex,
  if (p.blockIndex != null) 'bloque': p.blockIndex,
  if (p.prescriptionIndex != null) 'prescripcion': p.prescriptionIndex,
  if (p.setIndex != null) 'serie': p.setIndex,
};
