import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/list_all_clubs/list_all_clubs.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(RequestContext context) => switch (context.request.method) {
      HttpMethod.get => listAllClubsEndpoint(context),
      _ => Future.value(metodoNoPermitido()),
    };
