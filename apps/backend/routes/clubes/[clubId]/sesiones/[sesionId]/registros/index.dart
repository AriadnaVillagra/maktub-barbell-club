import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/sesion/record_set/record_set.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(
  RequestContext context,
  String clubId,
  String sesionId,
) => switch (context.request.method) {
  HttpMethod.put => recordSetEndpoint(context, sesionId),
  _ => Future.value(metodoNoPermitido()),
};
