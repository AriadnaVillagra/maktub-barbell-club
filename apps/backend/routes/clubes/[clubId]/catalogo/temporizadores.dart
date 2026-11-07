import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/catalogo/read_catalog/read_catalog.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(RequestContext context) => switch (context.request.method) {
  HttpMethod.get => listTimersEndpoint(context),
  _ => Future.value(metodoNoPermitido()),
};
