import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/sesion/proposed_loads/proposed_loads.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(
  RequestContext context,
  String clubId,
  String sesionId,
  String atletaId,
) => switch (context.request.method) {
  HttpMethod.get => proposedLoadsEndpoint(context, sesionId, atletaId),
  _ => Future.value(metodoNoPermitido()),
};
