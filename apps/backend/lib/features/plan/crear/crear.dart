import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'crear_store.dart';

/// `POST /clubes/{clubId}/planes` body `{nombre, tipo?}` (`tipo` is `regular` or `test`, default `regular`)
/// → 201 with the created plan: no week models and no assignment yet (they are saved whole in E5.3).
/// Needs [Accion.planificar] (the coach). The server sets `id`, `clubId` and `auditoria`.
/// [store], [newId] and [now] are for tests.
Future<Response> createPlanEndpoint(
  RequestContext context, {
  CreatePlanStore? store,
  String Function()? newId,
  DateTime Function()? now,
}) async {
  final club = context.read<ClubContext>().authorize(Accion.planificar);
  final body = await leerCuerpoJson(context.request);
  final plan = await CreatePlan(
    store ?? MongoCreatePlanStore(context.read<Db>()),
    newId: newId,
    now: now,
  )(club, body);
  return Response.json(statusCode: HttpStatus.created, body: plan.toJson());
}

class CreatePlan {
  CreatePlan(this._store, {String Function()? newId, DateTime Function()? now})
    : _newId = newId ?? (() => ObjectId().oid),
      _now = now ?? DateTime.now;

  final CreatePlanStore _store;
  final String Function() _newId;
  final DateTime Function() _now;

  Future<Plan> call(ClubContext club, Json body) async {
    final rawName = body['nombre'];
    final name = rawName is String ? rawName.trim() : '';
    if (name.isEmpty) {
      throw const ErrorDeSolicitud('El nombre del plan es obligatorio.');
    }
    final PlanType type;
    try {
      type = body['tipo'] == null
          ? PlanType.regular
          : PlanType.deCable(body['tipo']);
    } on FormatException {
      throw const ErrorDeSolicitud(
        'El tipo de plan debe ser "regular" o "test".',
      );
    }
    final plan = Plan(
      id: _newId(),
      clubId: club.clubId,
      name: name,
      type: type,
      auditoria: Auditoria.nueva(club.userId, ahora: _now()),
    );
    await _store.insert(plan);
    return plan;
  }
}
