import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/sesion/day_status/day_status.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(
  RequestContext context,
  String clubId,
  String asignacionId,
) => switch (context.request.method) {
  HttpMethod.get => assignmentDayStatusEndpoint(context, asignacionId),
  _ => Future.value(metodoNoPermitido()),
};
