import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/asignaciones/set_athletes/set_athletes.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(
  RequestContext context,
  String clubId,
  String asignacionId,
) => switch (context.request.method) {
  HttpMethod.put => setAssignmentAthletesEndpoint(context, asignacionId),
  _ => Future.value(metodoNoPermitido()),
};
