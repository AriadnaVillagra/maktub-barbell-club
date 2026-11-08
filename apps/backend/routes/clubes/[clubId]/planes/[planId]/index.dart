import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/plan/guardar/guardar.dart';
import 'package:maktub_backend/features/plan/leer/leer.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(
  RequestContext context,
  String clubId,
  String planId,
) => switch (context.request.method) {
  HttpMethod.get => readPlanEndpoint(context, planId),
  HttpMethod.put => savePlanEndpoint(context, planId),
  _ => Future.value(metodoNoPermitido()),
};
