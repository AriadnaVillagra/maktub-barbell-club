import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/auth/end_session/end_session.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(RequestContext context) => switch (context.request.method) {
      HttpMethod.post => endSessionEndpoint(context),
      _ => Future.value(metodoNoPermitido()),
    };
