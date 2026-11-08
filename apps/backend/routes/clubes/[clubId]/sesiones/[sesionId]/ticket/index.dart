import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/sesion/request_live_ticket/request_live_ticket.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(
  RequestContext context,
  String clubId,
  String sesionId,
) => switch (context.request.method) {
  HttpMethod.post => requestLiveTicketEndpoint(context, sesionId),
  _ => Future.value(metodoNoPermitido()),
};
