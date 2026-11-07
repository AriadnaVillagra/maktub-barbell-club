import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/auth/google_login/google_login.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(RequestContext context) => switch (context.request.method) {
      HttpMethod.post => googleLoginEndpoint(context),
      _ => Future.value(metodoNoPermitido()),
    };
