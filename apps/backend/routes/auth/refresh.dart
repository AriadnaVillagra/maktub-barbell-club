import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/auth/refresh_session/refresh_session.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(RequestContext context) => switch (context.request.method) {
      HttpMethod.post => refreshSessionEndpoint(context),
      _ => Future.value(metodoNoPermitido()),
    };
