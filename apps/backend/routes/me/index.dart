import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/auth/who_am_i/who_am_i.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(RequestContext context) => switch (context.request.method) {
      HttpMethod.get => whoAmIEndpoint(context),
      _ => Future.value(metodoNoPermitido()),
    };
