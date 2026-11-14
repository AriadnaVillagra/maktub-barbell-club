import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/sesion/record_block_time/record_block_time.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(
  RequestContext context,
  String clubId,
  String sesionId,
  String tiempoId,
) => switch (context.request.method) {
  HttpMethod.put => recordBlockTimeEndpoint(context, sesionId, tiempoId),
  _ => Future.value(metodoNoPermitido()),
};
