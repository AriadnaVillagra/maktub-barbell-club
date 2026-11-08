import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/factores/fijar_factor/fijar_factor.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(
  RequestContext context,
  String clubId,
  String athleteId,
) => switch (context.request.method) {
  HttpMethod.post => setFactorEndpoint(context, athleteId),
  _ => Future.value(metodoNoPermitido()),
};
