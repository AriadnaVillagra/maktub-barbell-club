import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/wods/wod_body.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'guardar_store.dart';

/// `PUT /clubes/{clubId}/wods/{wodId}` body: the whole WoD as `Wod.toJson()` → 200 with the saved WoD. It
/// replaces the stored WoD in one document write. The server sets `id` (the URL's), `clubId` and the audit
/// (creation is kept from the stored WoD; modification is the caller and now): the body's are ignored.
/// 404 if the WoD does not exist in the club; 422 `{error, problemas}`, writing nothing, for a WoD without
/// name or with a prescription without exercise. Plans that already copied the WoD are not touched.
/// Needs [Accion.planificar]. [store] and [now] are for tests.
Future<Response> saveWodEndpoint(
  RequestContext context,
  String wodId, {
  SaveWodStore? store,
  DateTime Function()? now,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.planificar);
  final body = await leerCuerpoJson(context.request);
  final wod = await SaveWod(
    store ?? MongoSaveWodStore(context.read<Db>()),
    now: now,
  )(club, wodId, body);
  return Response.json(body: wod.toJson());
}

class SaveWod {
  SaveWod(this._store, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final SaveWodStore _store;
  final DateTime Function() _now;

  Future<Wod> call(ClubContext club, String wodId, Json body) async {
    final stored = await _store.wod(club.clubId, wodId);
    if (stored == null) {
      throw const ErrorDeSolicitud.noEncontrado('WoD no encontrado.');
    }
    final wod = wodFromBody(
      body,
      id: stored.id,
      clubId: club.clubId,
      auditoria: stored.auditoria.modificada(club.userId, ahora: _now()),
    );
    if (!await _store.replace(wod)) {
      throw const ErrorDeSolicitud.noEncontrado('WoD no encontrado.');
    }
    return wod;
  }
}
