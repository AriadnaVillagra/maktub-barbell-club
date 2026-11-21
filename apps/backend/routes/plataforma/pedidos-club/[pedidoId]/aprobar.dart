import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/club_requests/approve_club_request/approve_club_request.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(RequestContext context, String pedidoId) => switch (context.request.method) {
      HttpMethod.post => approveClubRequestEndpoint(context, pedidoId),
      _ => Future.value(metodoNoPermitido()),
    };
