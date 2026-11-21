// ignore_for_file: file_names

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/history/session_history/session_history.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(
  RequestContext context,
  String clubId,
  String athleteId,
  String sessionId,
) => switch (context.request.method) {
  HttpMethod.get => sessionHistoryEndpoint(context, athleteId, sessionId),
  _ => Future.value(metodoNoPermitido()),
};
