import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/club_requests/request_club/request_club.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(RequestContext context) => switch (context.request.method) {
      HttpMethod.post => requestClubEndpoint(context),
      _ => Future.value(metodoNoPermitido()),
    };
