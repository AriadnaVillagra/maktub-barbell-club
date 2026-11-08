import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/asignaciones/terminar/terminar.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(
  RequestContext context,
  String clubId,
  String asignacionId,
) => switch (context.request.method) {
  HttpMethod.post => endAssignmentEndpoint(context, asignacionId),
  _ => Future.value(metodoNoPermitido()),
};
