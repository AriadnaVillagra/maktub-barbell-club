import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'publicado_store.dart';

/// `GET /clubes/{clubId}/planes/{planId}/publicado` → `{id, nombre, tipo, modelosSemana, asignacion,
/// publicadoEn}` taken from the published copy only, never from the draft. Needs
/// [Accion.verCatalogoYPlanes] (athletes too). 404 if the plan is not in the club or was never published.
/// [store] is for tests.
Future<Response> readPublishedPlanEndpoint(
  RequestContext context,
  String planId, {
  ReadPublishedPlanStore? store,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.verCatalogoYPlanes);
  final body = await ReadPublishedPlan(
    store ?? MongoReadPublishedPlanStore(context.read<Db>()),
  )(club, planId);
  return Response.json(body: body);
}

class ReadPublishedPlan {
  ReadPublishedPlan(this._store);

  final ReadPublishedPlanStore _store;

  Future<Json> call(ClubContext club, String planId) async {
    final plan = await _store.plan(club.clubId, planId);
    final published = plan?.published;
    if (plan == null || published == null) {
      throw const ErrorDeSolicitud.noEncontrado(
        'El plan no tiene una versión publicada.',
      );
    }
    return {
      'id': plan.id,
      'nombre': plan.name,
      'tipo': plan.type.cable,
      'modelosSemana': [for (final m in published.weekModels) m.toJson()],
      'asignacion': published.weekAssignment,
      'publicadoEn': published.publishedAt.toUtc().toIso8601String(),
    };
  }
}
