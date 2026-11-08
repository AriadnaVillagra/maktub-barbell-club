import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/wods/borrar/borrar.dart';
import 'package:maktub_backend/features/wods/guardar/guardar.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(
  RequestContext context,
  String clubId,
  String wodId,
) => switch (context.request.method) {
  HttpMethod.put => saveWodEndpoint(context, wodId),
  HttpMethod.delete => deleteWodEndpoint(context, wodId),
  _ => Future.value(metodoNoPermitido()),
};
