import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/asignaciones/ubicacion_atleta/ubicacion_atleta.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(
  RequestContext context,
  String clubId,
  String athleteId,
) => switch (context.request.method) {
  HttpMethod.get => athleteLocationEndpoint(context, athleteId),
  _ => Future.value(metodoNoPermitido()),
};
