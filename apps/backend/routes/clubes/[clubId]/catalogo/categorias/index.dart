import 'package:dart_frog/dart_frog.dart';
import 'package:maktub_backend/features/catalogo/read_catalog/read_catalog.dart';
import 'package:maktub_backend/features/catalogo/write_category/write_category.dart';
import 'package:maktub_backend/infraestructura/http.dart';

Future<Response> onRequest(RequestContext context, String clubId) => switch (context.request.method) {
  HttpMethod.get => listCategoriesEndpoint(context),
  HttpMethod.post => createCategoryEndpoint(context),
  _ => Future.value(metodoNoPermitido()),
};
