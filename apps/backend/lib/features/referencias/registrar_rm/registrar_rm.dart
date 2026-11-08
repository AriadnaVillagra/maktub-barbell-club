import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'registrar_rm_store.dart';

/// `POST /clubes/{clubId}/atletas/{athleteId}/referencias` body `{ejercicioId, valor, fecha}` (`fecha` is
/// `yyyy-MM-dd`) → the created `rm` reference. Needs [Accion.editarReferencias] (the coach).
///
/// It is one insert: nothing is modified and no work factor is written. The factor reads 100 % again
/// because a factor older than the RM in force does not count (`currentWorkFactor`, design D15).
/// The server sets `id`, `clubId`, `atletaId`, `tipo`, `origen` and `auditoria`. [store], [newId] and
/// [now] are for tests.
Future<Response> registerRmEndpoint(
  RequestContext context,
  String athleteId, {
  RegisterRmStore? store,
  String Function()? newId,
  DateTime Function()? now,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.editarReferencias);
  final body = await leerCuerpoJson(context.request);
  final created = await RegisterRm(
    store ?? MongoRegisterRmStore(context.read<Db>()),
    newId: newId,
    now: now,
  )(club, athleteId, body);
  return Response.json(body: created.toJson());
}

class RegisterRm {
  RegisterRm(this._store, {String Function()? newId, DateTime Function()? now})
    : _newId = newId ?? (() => ObjectId().oid),
      _now = now ?? DateTime.now;

  final RegisterRmStore _store;
  final String Function() _newId;
  final DateTime Function() _now;

  Future<Reference> call(ClubContext club, String athleteId, Json body) async {
    // Only `rm` is accepted in M1; the other types have no screen yet.
    final type = body['tipo'];
    if (type != null && type != ReferenceType.rm.cable) {
      throw const ErrorDeSolicitud(
        'Solo se pueden registrar referencias de tipo "rm".',
      );
    }
    final exerciseId = body['ejercicioId'];
    if (exerciseId is! String || exerciseId.isEmpty) {
      throw const ErrorDeSolicitud('El ejercicio es obligatorio.');
    }
    final value = body['valor'];
    if (value is! num || !value.isFinite || value <= 0) {
      throw const ErrorDeSolicitud('El valor debe ser un número mayor que 0.');
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
      throw const ErrorDeSolicitud(
        'El ejercicio no existe.',
        estado: HttpStatus.badRequest,
      );
    }

    final reference = Reference(
      id: _newId(),
      clubId: club.clubId,
      athleteId: athleteId,
      exerciseId: exerciseId,
      type: ReferenceType.rm,
      value: value.toDouble(),
      date: date,
      // The docs do not say which origin a hand-loaded RM has; `testeado` is the one they mention with it.
      origin: ReferenceOrigin.testeado,
      auditoria: Auditoria.nueva(club.userId, ahora: _now()),
    );
    await _store.insert(reference);
    return reference;
  }
}
