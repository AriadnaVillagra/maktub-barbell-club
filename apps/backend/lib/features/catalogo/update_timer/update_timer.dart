import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'update_timer_store.dart';

/// `PUT /clubes/{clubId}/temporizadores/{id}` → the edited timer.
Future<Response> updateTimerEndpoint(RequestContext context, String id, {UpdateTimerStore? store}) async {
  final club = context.read<ClubContext>();
  final body = await leerCuerpoJson(context.request);
  final timer = await UpdateTimer(store ?? MongoUpdateTimerStore(context.read<Db>()))(club, id, body);
  return Response.json(body: timer.toJson());
}

/// Edits a timer. A default one needs a platform admin, and the change reaches every club.
class UpdateTimer {
  UpdateTimer(this._store, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final UpdateTimerStore _store;
  final DateTime Function() _now;

  Future<Temporizador> call(ClubContext club, String id, Json body) async {
    final current = await _store.findVisible(club.clubId, id);
    if (current == null) throw const ErrorDeSolicitud.noEncontrado('Temporizador no encontrado.');
    club.authorizeCatalogWrite(current);
    // Only the content changes: id, scope and audit trail are not the client's to set.
    final merged = Temporizador.fromJson({...current.toJson(), ...body, 'id': current.id, 'clubId': current.clubId});
    final edited = merged.copyWith(
      auditoria: (current.auditoria ?? Auditoria.nueva(club.userId, ahora: _now())).modificada(
        club.userId,
        ahora: _now(),
      ),
    );
    final problems = edited.validar();
    if (problems.isNotEmpty) {
      throw ErrorDeSolicitud('Temporizador inválido: ${problems.map((p) => p.name).join(', ')}.');
    }
    await _store.replace(edited);
    return edited;
  }
}
