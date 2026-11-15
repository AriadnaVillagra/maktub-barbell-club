import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/sesion/assignment_proposed_loads/assignment_proposed_loads.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(
  RequestContext context,
  String clubId,
  String asignacionId,
) => switch (context.request.method) {
  HttpMethod.get => assignmentProposedLoadsEndpoint(context, asignacionId),
  _ => Future.value(metodoNoPermitido()),
};
