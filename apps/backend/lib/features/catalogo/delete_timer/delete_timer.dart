import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/plan/usage/usage.dart';
import 'package:maktub_backend/features/plan/usage/usage_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'delete_timer_store.dart';

/// `DELETE /clubes/{clubId}/temporizadores/{id}` → `{resultado: 'borrado' | 'archivado'}`.
/// A used timer is archived instead of deleted (F2 §5).
Future<Response> deleteTimerEndpoint(
  RequestContext context,
  String id, {
  DeleteTimerStore? store,
  TimerUsage? usage,
}) async {
  final club = context.read<ClubContext>();
  final result = await DeleteTimer(
    store ?? MongoDeleteTimerStore(context.read<Db>()),
    usage ?? PlanTimerUsage(MongoPlanUsageStore(context.read<Db>())),
  )(club, id);
  return Response.json(body: {'resultado': result.name});
}

enum DeleteTimerResult { borrado, archivado }

class DeleteTimer {
  DeleteTimer(this._store, this._usage, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DeleteTimerStore _store;
  final TimerUsage _usage;
  final DateTime Function() _now;

  Future<DeleteTimerResult> call(ClubContext club, String id) async {
    final current = await _store.findVisible(club.clubId, id);
    if (current == null) throw const ErrorDeSolicitud.noEncontrado('Temporizador no encontrado.');
    club.authorizeCatalogWrite(current);
    if (!await _usage.isUsed(current.clubId, id)) {
      await _store.delete(current.clubId, id);
      return DeleteTimerResult.borrado;
    }
    if (current.estado != CatalogStatus.archived) {
      await _store.replace(
        current.copyWith(
          estado: CatalogStatus.archived,
          auditoria: (current.auditoria ?? Auditoria.nueva(club.userId, ahora: _now())).modificada(
            club.userId,
            ahora: _now(),
          ),
        ),
      );
    }
    return DeleteTimerResult.archivado;
  }
}
