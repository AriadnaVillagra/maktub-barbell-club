import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/asignaciones/crear/crear.dart';
import 'package:maktub_backend/features/asignaciones/listar/listar.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(RequestContext context, String clubId) =>
    switch (context.request.method) {
      HttpMethod.get => listAssignmentsEndpoint(context),
      HttpMethod.post => createAssignmentEndpoint(context),
      _ => Future.value(metodoNoPermitido()),
    };
