import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/history/list_history/list_history.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(
  RequestContext context,
  String clubId,
  String athleteId,
) => switch (context.request.method) {
  HttpMethod.get => listHistoryEndpoint(context, athleteId),
  _ => Future.value(metodoNoPermitido()),
};
