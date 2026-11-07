import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/catalogo/data/http_catalog_repository.dart';

void main() {
  final audit = Auditoria(
    creadoPor: 'u1',
    creadoEn: DateTime.utc(2026, 11, 7),
  ).toJson();

  test('asks the catalog endpoints of the club and parses them', () async {
    final urls = <Uri>[];
    final repo = HttpCatalogRepository(
      ClienteApi(
        base: Uri.parse('http://api.test'),
        cliente: MockClient((req) async {
          urls.add(req.url);
          final body = req.url.path.endsWith('categorias')
              ? {
                  'categorias': [
                    {
                      'id': 'k1',
                      'clubId': 'c1',
                      'nombre': 'Fuerza',
                      'auditoria': audit,
                    },
                  ],
                }
              : {
                  'ejercicios': [
                    {
                      'id': 'e1',
                      'clubId': 'c1',
                      'nombre': 'Sentadilla',
                      'categorias': ['k1'],
                      'auditoria': audit,
                    },
                  ],
                };
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final exercises = await repo.exercises(
      'c1',
      categoryId: 'k1',
      status: CatalogStatus.active,
    );
    final categories = await repo.categories('c1');

    expect(exercises.single.name, 'Sentadilla');
    expect(categories.single.name, 'Fuerza');
    expect(urls[0].path, '/clubes/c1/catalogo/ejercicios');
    expect(urls[0].queryParameters, {'categoria': 'k1', 'estado': 'activo'});
    expect(urls[1].path, '/clubes/c1/catalogo/categorias');
  });
}
