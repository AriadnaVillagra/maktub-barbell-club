import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/sesion/write_guided_pass/write_guided_pass.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(
  RequestContext context,
  String clubId,
  String sesionId,
) => switch (context.request.method) {
  HttpMethod.post => writeGuidedPassEndpoint(context, sesionId),
  _ => Future.value(metodoNoPermitido()),
};
