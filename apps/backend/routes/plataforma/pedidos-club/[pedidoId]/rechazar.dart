import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/club_requests/reject_club_request/reject_club_request.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(RequestContext context, String pedidoId) => switch (context.request.method) {
      HttpMethod.post => rejectClubRequestEndpoint(context, pedidoId),
      _ => Future.value(metodoNoPermitido()),
    };
