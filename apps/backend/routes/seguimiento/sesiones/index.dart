import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/seguimiento/guardar_sesion/guardar_sesion.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(RequestContext context) async => switch (context.request.method) {
      HttpMethod.put => guardarSesionEndpoint(context),
      _ => metodoNoPermitido(),
    };
