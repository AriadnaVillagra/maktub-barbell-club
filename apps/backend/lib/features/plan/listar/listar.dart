import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'listar_store.dart';

/// `GET /clubes/{clubId}/planes` → `[{id, nombre, tipo, pasado, cantidadModelos, publicado, cambiosSinPublicar, actualizadoEn}]`, sorted by
/// `nombre` (case-insensitive, ties broken by id). `actualizadoEn` is the last modification instant, or the
/// creation one if never modified. `publicado` is whether the plan has a published version and
/// `cambiosSinPublicar` whether the saved content differs from it (always true while never published).
/// Only the plans the caller can see ([PlanAccess]); each one also says its `visibilidad`, whether the caller
/// created it (`propio`), can change it (`puedeEditar`) and can delete it or change its visibility
/// (`puedeGestionar`). Needs [Accion.planificar] (the coach). [store] is for tests.
Future<Response> listPlansEndpoint(
  RequestContext context, {
  ListPlansStore? store,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.planificar);
  final plans = await ListPlans(
    store ?? MongoListPlansStore(context.read<Db>()),
  )(club);
  return Response.json(body: plans);
}

class ListPlans {
  ListPlans(this._store);

  final ListPlansStore _store;

  Future<List<Json>> call(ClubContext club) async {
    PlanAccess accessOf(Plan p) => PlanAccess.of(p, userId: club.userId, roles: club.roles);
    final plans = [
      for (final p in await _store.plans(club.clubId))
        if (accessOf(p).see) p,
    ]..sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : a.id.compareTo(b.id);
      });
    return [
      for (final p in plans)
        for (final access in [accessOf(p)])
        {
          'id': p.id,
          'nombre': p.name,
          'tipo': p.type.cable,
          'pasado': p.isPast,
          'cantidadModelos': p.weekModels.length,
          'publicado': p.published != null,
          'cambiosSinPublicar': p.hasUnpublishedChanges,
          'visibilidad': p.visibility.cable,
          'propio': p.auditoria.creadoPor == club.userId,
          'puedeEditar': access.edit,
          'puedeGestionar': access.manage,
          'actualizadoEn': (p.auditoria.modificadoEn ?? p.auditoria.creadoEn)
              .toUtc()
              .toIso8601String(),
        },
    ];
  }
}
