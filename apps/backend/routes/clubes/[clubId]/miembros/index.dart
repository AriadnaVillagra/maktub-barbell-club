import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/acceso/members/members.dart';

Future<Response> onRequest(RequestContext context, String clubId) async => switch (context.request.method) {
  HttpMethod.get => listMembersEndpoint(context),
  HttpMethod.post => registerMemberEndpoint(context),
  _ => Response(statusCode: HttpStatus.methodNotAllowed),
};
