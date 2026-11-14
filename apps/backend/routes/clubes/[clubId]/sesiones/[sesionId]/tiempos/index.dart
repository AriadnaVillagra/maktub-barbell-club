import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/sesion/block_times/block_times.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(
  RequestContext context,
  String clubId,
  String sesionId,
) => switch (context.request.method) {
  HttpMethod.get => blockTimesEndpoint(context, sesionId),
  _ => Future.value(metodoNoPermitido()),
};
