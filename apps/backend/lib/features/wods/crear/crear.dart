import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/wods/wod_body.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'crear_store.dart';

/// `POST /clubes/{clubId}/wods` body: a WoD as `Wod.toJson()` (`nombre`, `descripcion?`, `temporizadorId?`,
/// `prescripciones`) → 201 with the created WoD. The server sets `id`, `clubId` and `auditoria`: the body's are
/// ignored. A WoD without name or with a prescription without exercise is 422 `{error, problemas}` and writes
/// nothing. Needs [Accion.planificar] (the coach). [store], [newId] and [now] are for tests.
Future<Response> createWodEndpoint(
  RequestContext context, {
  CreateWodStore? store,
  String Function()? newId,
  DateTime Function()? now,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.planificar);
  final body = await leerCuerpoJson(context.request);
  final wod = await CreateWod(
    store ?? MongoCreateWodStore(context.read<Db>()),
    newId: newId,
    now: now,
  )(club, body);
  return Response.json(statusCode: HttpStatus.created, body: wod.toJson());
}

class CreateWod {
  CreateWod(this._store, {String Function()? newId, DateTime Function()? now})
    : _newId = newId ?? (() => ObjectId().oid),
      _now = now ?? DateTime.now;

  final CreateWodStore _store;
  final String Function() _newId;
  final DateTime Function() _now;

  Future<Wod> call(ClubContext club, Json body) async {
    final wod = wodFromBody(
      body,
      id: _newId(),
      clubId: club.clubId,
      auditoria: Auditoria.nueva(club.userId, ahora: _now()),
    );
    await _store.insert(wod);
    return wod;
  }
}
