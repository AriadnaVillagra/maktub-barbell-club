import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/plan/crear/crear.dart';
import 'package:maktub_backend/features/plan/listar/listar.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(RequestContext context, String clubId) =>
    switch (context.request.method) {
      HttpMethod.get => listPlansEndpoint(context),
      HttpMethod.post => createPlanEndpoint(context),
      _ => Future.value(metodoNoPermitido()),
    };
