import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'archive_timer_store.dart';

/// `POST /clubes/{clubId}/temporizadores/{id}/archivar` → the archived timer. Coaches only (`planificar`).
Future<Response> archiveTimerEndpoint(RequestContext context, String id, {ArchiveTimerStore? store}) async {
  final club = context.read<ClubContext>().authorize(Accion.planificar);
  final timer = await ArchiveTimer(store ?? MongoArchiveTimerStore(context.read<Db>()))(club, id);
  return Response.json(body: timer.toJson());
}

/// Archives a timer of the club: it stops being offered but still resolves where it was used.
/// Archiving an archived timer is a no-op. Base timers are read-only from a club.
class ArchiveTimer {
  ArchiveTimer(this._store, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final ArchiveTimerStore _store;
  final DateTime Function() _now;

  Future<Temporizador> call(ClubContext club, String id) async {
    final current = await _store.findVisible(club.clubId, id);
    if (current == null) throw const ErrorDeSolicitud.noEncontrado('Temporizador no encontrado.');
    if (scopeOf(current) == CatalogScope.base) {
      throw const ErrorDeSolicitud('Un temporizador base no se archiva desde un club.', estado: 403);
    }
    if (current.estado == CatalogStatus.archived) return current;
    final archived = current.copyWith(
      estado: CatalogStatus.archived,
      auditoria: (current.auditoria ?? Auditoria.nueva(club.userId, ahora: _now())).modificada(
        club.userId,
        ahora: _now(),
      ),
    );
    await _store.replace(archived);
    return archived;
  }
}
