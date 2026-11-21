import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/club_requests/list_club_requests/list_club_requests.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(RequestContext context) => switch (context.request.method) {
      HttpMethod.get => listClubRequestsEndpoint(context),
      _ => Future.value(metodoNoPermitido()),
    };
