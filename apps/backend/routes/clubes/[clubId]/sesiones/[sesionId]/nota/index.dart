import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/sesion/set_session_note/set_session_note.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(
  RequestContext context,
  String clubId,
  String sesionId,
) => switch (context.request.method) {
  HttpMethod.put => setSessionNoteEndpoint(context, sesionId),
  _ => Future.value(metodoNoPermitido()),
};
