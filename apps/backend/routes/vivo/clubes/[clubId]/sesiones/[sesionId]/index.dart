import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/sesion/connect_live_session/connect_live_session.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(
  RequestContext context,
  String clubId,
  String sesionId,
) => switch (context.request.method) {
  HttpMethod.get => connectLiveSessionEndpoint(context, clubId, sesionId),
  _ => Future.value(metodoNoPermitido()),
};
