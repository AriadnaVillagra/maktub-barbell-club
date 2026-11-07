import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/catalogo/create_timer/create_timer.dart';
import 'package:maktub_backend/infraestructura/http.dart';

// Reads live under `catalogo/temporizadores`; each slice checks its own action.
Future<Response> onRequest(RequestContext context, String clubId) => switch (context.request.method) {
  HttpMethod.post => createTimerEndpoint(context),
  _ => Future.value(metodoNoPermitido()),
};
