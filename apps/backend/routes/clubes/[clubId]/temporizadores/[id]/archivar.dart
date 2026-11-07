import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/catalogo/archive_timer/archive_timer.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(RequestContext context, String clubId, String id) => switch (context.request.method) {
  HttpMethod.post => archiveTimerEndpoint(context, id),
  _ => Future.value(metodoNoPermitido()),
};
