import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/seguimiento/obtener_seguimiento/obtener_seguimiento.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(RequestContext context) async => switch (context.request.method) {
      HttpMethod.get => obtenerSeguimientoEndpoint(context),
      _ => metodoNoPermitido(),
    };
