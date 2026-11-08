import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/grupos/listar/listar.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(RequestContext context, String clubId) =>
    switch (context.request.method) {
      HttpMethod.get => listGroupsEndpoint(context),
      _ => Future.value(metodoNoPermitido()),
    };
