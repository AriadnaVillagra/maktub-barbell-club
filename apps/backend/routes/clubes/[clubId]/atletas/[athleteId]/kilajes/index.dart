import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/kilajes/fijar_kilaje/fijar_kilaje.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(
  RequestContext context,
  String clubId,
  String athleteId,
) => switch (context.request.method) {
  HttpMethod.put => setFixedWeightEndpoint(context, athleteId),
  _ => Future.value(metodoNoPermitido()),
};
