import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/sesion/session_changes/session_changes.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(
  RequestContext context,
  String clubId,
  String sesionId,
) => switch (context.request.method) {
  HttpMethod.get => sessionChangesEndpoint(context, sesionId),
  _ => Future.value(metodoNoPermitido()),
};
