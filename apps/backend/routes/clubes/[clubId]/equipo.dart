import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/catalogo/get_team/get_team.dart';
import 'package:maktub_backend/features/catalogo/save_team/save_team.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(RequestContext context) => switch (context.request.method) {
  HttpMethod.get => getTeamEndpoint(context),
  HttpMethod.put => saveTeamEndpoint(context),
  _ => Future.value(metodoNoPermitido()),
};
