import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'fijar_factor_store.dart';

/// `POST /clubes/{clubId}/atletas/{athleteId}/factores` body `{ejercicioId, valor, fecha}` (`valor` is a
/// percent, `fecha` is `yyyy-MM-dd`) → the created work factor. Needs [Accion.editarReferencias] (the coach).
///
/// It is one insert: earlier entries of the history stay untouched. The server sets `id`, `clubId`,
/// `atletaId` and `auditoria`. [store], [newId] and [now] are for tests.
Future<Response> setFactorEndpoint(
  RequestContext context,
  String athleteId, {
  SetFactorStore? store,
  String Function()? newId,
  DateTime Function()? now,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.editarReferencias);
  final body = await leerCuerpoJson(context.request);
  final created = await SetFactor(
    store ?? MongoSetFactorStore(context.read<Db>()),
    newId: newId,
    now: now,
  )(club, athleteId, body);
  return Response.json(body: created.toJson());
}

class SetFactor {
  SetFactor(this._store, {String Function()? newId, DateTime Function()? now})
    : _newId = newId ?? (() => ObjectId().oid),
      _now = now ?? DateTime.now;

  final SetFactorStore _store;
  final String Function() _newId;
  final DateTime Function() _now;

  Future<WorkFactor> call(ClubContext club, String athleteId, Json body) async {
    final exerciseId = body['ejercicioId'];
    if (exerciseId is! String || exerciseId.isEmpty) {
      throw const ErrorDeSolicitud('El ejercicio es obligatorio.');
    }
    final value = body['valor'];
    if (value is! num || !value.isFinite || value <= 0) {
      throw const ErrorDeSolicitud('El factor debe ser un número mayor que 0.');
    }
    final rawDate = body['fecha'];
    if (rawDate is! String) {
      throw const ErrorDeSolicitud('La fecha es obligatoria (yyyy-MM-dd).');
    }
    final DateTime date;
    try {
      date = desdeIsoFecha(rawDate);
    } on Object {
      throw const ErrorDeSolicitud(
        'La fecha debe tener el formato yyyy-MM-dd.',
      );
    }

    if (!await _store.athleteInClub(club.clubId, athleteId)) {
      throw const ErrorDeSolicitud.noEncontrado('Atleta no encontrado.');
    }
    if (!await _store.exerciseVisible(club.clubId, exerciseId)) {
      throw const ErrorDeSolicitud('El ejercicio no existe.');
    }

    final factor = WorkFactor(
      id: _newId(),
      clubId: club.clubId,
      athleteId: athleteId,
      exerciseId: exerciseId,
      value: value.toDouble(),
      date: date,
      auditoria: Auditoria.nueva(club.userId, ahora: _now()),
    );
    await _store.insert(factor);
    return factor;
  }
}
