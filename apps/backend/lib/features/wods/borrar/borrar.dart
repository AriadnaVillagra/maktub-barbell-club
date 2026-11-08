import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'borrar_store.dart';

/// `DELETE /clubes/{clubId}/wods/{wodId}` → 204. A WoD is always deleted, even if it was used: plans store a
/// copy, so nothing refers to it. 404 if it does not exist in the club. Needs [Accion.planificar].
/// [store] is for tests.
Future<Response> deleteWodEndpoint(
  RequestContext context,
  String wodId, {
  DeleteWodStore? store,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.planificar);
  await DeleteWod(store ?? MongoDeleteWodStore(context.read<Db>()))(
    club,
    wodId,
  );
  return Response(statusCode: HttpStatus.noContent);
}

class DeleteWod {
  DeleteWod(this._store);

  final DeleteWodStore _store;

  Future<void> call(ClubContext club, String wodId) async {
    if (!await _store.delete(club.clubId, wodId)) {
      throw const ErrorDeSolicitud.noEncontrado('WoD no encontrado.');
    }
  }
}
