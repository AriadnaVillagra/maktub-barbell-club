import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'quick_timers_store.dart';

/// `GET /clubes/{clubId}/temporizadores-a-mano` → `{temporizadorIds: [...]}`: the timers the caller keeps at hand in the
/// club, empty until they choose some. Any member (`verCatalogoYPlanes`). [store] is for tests.
Future<Response> getQuickTimersEndpoint(RequestContext context, {QuickTimersStore? store}) async {
  final club = context.read<ClubContext>().authorize(Accion.verCatalogoYPlanes);
  final found = await (store ?? MongoQuickTimersStore(context.read<Db>())).find(club.clubId, club.userId);
  return Response.json(body: {'temporizadorIds': found?.timerIds ?? const <String>[]});
}

/// `PUT /clubes/{clubId}/temporizadores-a-mano` body `{temporizadorIds: [...]}` → the same, as saved. Replaces the
/// caller's whole choice; each one only touches their own. Every id must be a timer the club can use (its own or a
/// platform one): 400 otherwise, and nothing is written. Repeated ids count once. [store] is for tests.
Future<Response> saveQuickTimersEndpoint(RequestContext context, {QuickTimersStore? store}) async {
  final club = context.read<ClubContext>().authorize(Accion.verCatalogoYPlanes);
  final saved = await SaveQuickTimers(store ?? MongoQuickTimersStore(context.read<Db>()))(
    club,
    await leerCuerpoJson(context.request),
  );
  return Response.json(body: {'temporizadorIds': saved.timerIds});
}

class SaveQuickTimers {
  SaveQuickTimers(this._store);

  final QuickTimersStore _store;

  Future<QuickTimers> call(ClubContext club, Json body) async {
    final raw = body['temporizadorIds'];
    if (raw is! List || raw.any((id) => id is! String)) {
      throw const ErrorDeSolicitud('"temporizadorIds" tiene que ser una lista de ids.');
    }
    final ids = {for (final id in raw.cast<String>()) id}.toList();
    final known = await _store.timerIds(club.clubId);
    if (!ids.every(known.contains)) {
      throw const ErrorDeSolicitud('Alguno de los temporizadores no existe en el club.');
    }
    final quick = QuickTimers(clubId: club.clubId, userId: club.userId, timerIds: ids);
    await _store.save(quick);
    return quick;
  }
}
