// ignore_for_file: file_names

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/catalogo/delete_timer/delete_timer.dart';
import 'package:maktub_backend/features/catalogo/update_timer/update_timer.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(RequestContext context, String clubId, String id) => switch (context.request.method) {
  HttpMethod.put => updateTimerEndpoint(context, id),
  HttpMethod.delete => deleteTimerEndpoint(context, id),
  _ => Future.value(metodoNoPermitido()),
};
