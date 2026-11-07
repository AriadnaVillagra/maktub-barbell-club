import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'create_timer_store.dart';

/// `POST /clubes/{clubId}/temporizadores` → 201 with the new timer. Coaches only (`planificar`).
Future<Response> createTimerEndpoint(RequestContext context, {CreateTimerStore? store}) async {
  final club = context.read<ClubContext>().authorize(Accion.planificar);
  final body = await leerCuerpoJson(context.request);
  final timer = await CreateTimer(store ?? MongoCreateTimerStore(context.read<Db>()))(club, body);
  return Response.json(statusCode: HttpStatus.created, body: timer.toJson());
}

class CreateTimer {
  CreateTimer(this._store, {DateTime Function()? now, String Function()? newId})
    : _now = now ?? DateTime.now,
      _newId = newId ?? (() => ObjectId().oid);

  final CreateTimerStore _store;
  final DateTime Function() _now;
  final String Function() _newId;

  Future<Temporizador> call(ClubContext club, Json body) async {
    // The id, the scope, the status and the audit trail are the server's: whatever the body says is ignored.
    final timer = Temporizador.fromJson({
      ...body,
      'id': _newId(),
      'clubId': club.clubId,
      'estado': CatalogStatus.active.cable,
      'auditoria': null,
    }).copyWith(auditoria: Auditoria.nueva(club.userId, ahora: _now()));
    final problems = timer.validar();
    if (problems.isNotEmpty) {
      throw ErrorDeSolicitud('Temporizador inválido: ${problems.map((p) => p.name).join(', ')}.');
    }
    await _store.insert(timer);
    return timer;
  }
}
