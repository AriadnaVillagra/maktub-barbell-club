import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/catalogo/quick_timers/quick_timers.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(RequestContext context, String clubId) => switch (context.request.method) {
  HttpMethod.get => getQuickTimersEndpoint(context),
  HttpMethod.put => saveQuickTimersEndpoint(context),
  _ => Future.value(metodoNoPermitido()),
};
