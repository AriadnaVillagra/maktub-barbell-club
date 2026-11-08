import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/sesion/open_session/open_session.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(RequestContext context, String clubId) =>
    switch (context.request.method) {
      HttpMethod.post => openSessionEndpoint(context),
      _ => Future.value(metodoNoPermitido()),
    };
