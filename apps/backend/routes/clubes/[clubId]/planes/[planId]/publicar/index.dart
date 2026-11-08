import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/plan/publicar/publicar.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(
  RequestContext context,
  String clubId,
  String planId,
) => switch (context.request.method) {
  HttpMethod.post => publishPlanEndpoint(context, planId),
  _ => Future.value(metodoNoPermitido()),
};
