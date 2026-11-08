import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/atletas/listar_atletas/listar_atletas.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(RequestContext context, String clubId) =>
    switch (context.request.method) {
      HttpMethod.get => listAthletesEndpoint(context),
      _ => Future.value(metodoNoPermitido()),
    };
