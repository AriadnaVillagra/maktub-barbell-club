// ignore_for_file: file_names

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/catalogo/write_exercise/write_exercise.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(RequestContext context, String clubId, String id) => switch (context.request.method) {
  HttpMethod.put => updateExerciseEndpoint(context, id),
  HttpMethod.patch => setExerciseStatusEndpoint(context, id),
  HttpMethod.delete => deleteExerciseEndpoint(context, id),
  _ => Future.value(metodoNoPermitido()),
};
