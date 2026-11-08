import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/referencias/registrar_rm/registrar_rm.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(
  RequestContext context,
  String clubId,
  String athleteId,
) => switch (context.request.method) {
  HttpMethod.post => registerRmEndpoint(context, athleteId),
  _ => Future.value(metodoNoPermitido()),
};
