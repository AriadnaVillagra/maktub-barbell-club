// ignore_for_file: file_names

import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/catalogo/write_category/write_category.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(RequestContext context, String clubId, String id) => switch (context.request.method) {
  HttpMethod.put => updateCategoryEndpoint(context, id),
  HttpMethod.patch => setCategoryStatusEndpoint(context, id),
  HttpMethod.delete => deleteCategoryEndpoint(context, id),
  _ => Future.value(metodoNoPermitido()),
};
