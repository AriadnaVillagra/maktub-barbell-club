import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'fijar_kilaje_store.dart';

/// `PUT /clubes/{clubId}/atletas/{athleteId}/kilajes` body `{ejercicioId, kilos}` → the fixed weight.
/// Needs [Accion.editarReferencias] (the coach).
///
/// There is one document per (athlete, exercise): a second call replaces its value, keeping `id` and
/// the creation audit and stamping the modification. The server sets `id`, `clubId`, `atletaId` and
/// `auditoria`. [store], [newId] and [now] are for tests.
Future<Response> setFixedWeightEndpoint(
  RequestContext context,
  String athleteId, {
  SetFixedWeightStore? store,
  String Function()? newId,
  DateTime Function()? now,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.editarReferencias);
  final body = await leerCuerpoJson(context.request);
  final saved = await SetFixedWeight(
    store ?? MongoSetFixedWeightStore(context.read<Db>()),
    newId: newId,
    now: now,
  )(club, athleteId, body);
  return Response.json(body: saved.toJson());
}

class SetFixedWeight {
  SetFixedWeight(
    this._store, {
    String Function()? newId,
    DateTime Function()? now,
  }) : _newId = newId ?? (() => ObjectId().oid),
       _now = now ?? DateTime.now;

  final SetFixedWeightStore _store;
  final String Function() _newId;
  final DateTime Function() _now;

  Future<FixedWeight> call(
    ClubContext club,
    String athleteId,
    Json body,
  ) async {
    final exerciseId = body['ejercicioId'];
    if (exerciseId is! String || exerciseId.isEmpty) {
      throw const ErrorDeSolicitud('El ejercicio es obligatorio.');
    }
    final kg = body['kilos'];
    if (kg is! num || !kg.isFinite || kg <= 0) {
      throw const ErrorDeSolicitud(
        'Los kilos deben ser un número mayor que 0.',
      );
    }

    if (!await _store.athleteInClub(club.clubId, athleteId)) {
      throw const ErrorDeSolicitud.noEncontrado('Atleta no encontrado.');
    }
    if (!await _store.exerciseVisible(club.clubId, exerciseId)) {
      throw const ErrorDeSolicitud('El ejercicio no existe.');
    }

    final now = _now();
    final current = await _store.find(club.clubId, athleteId, exerciseId);
    final weight = FixedWeight(
      id: current?.id ?? _newId(),
      clubId: club.clubId,
      athleteId: athleteId,
      exerciseId: exerciseId,
      kg: kg.toDouble(),
      auditoria: current == null
          ? Auditoria.nueva(club.userId, ahora: now)
          : current.auditoria.modificada(club.userId, ahora: now),
    );
    await _store.save(weight);
    return weight;
  }
}
