import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/wods/crear/crear.dart';
import 'package:maktub_backend/features/wods/listar/listar.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(RequestContext context, String clubId) =>
    switch (context.request.method) {
      HttpMethod.get => listWodsEndpoint(context),
      HttpMethod.post => createWodEndpoint(context),
      _ => Future.value(metodoNoPermitido()),
    };
