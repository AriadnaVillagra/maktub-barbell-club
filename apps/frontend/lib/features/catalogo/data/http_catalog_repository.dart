import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/cliente_api.dart';
import '../domain/catalog_repository.dart';

class HttpCatalogRepository implements CatalogRepository {
  HttpCatalogRepository(this._client);

  final ClienteApi _client;

  @override
  Future<List<Exercise>> exercises(
    String clubId, {
    String? categoryId,
    CatalogStatus? status,
  }) async {
    final path = Uri(
      pathSegments: ['clubes', clubId, 'catalogo', 'ejercicios'],
      queryParameters: {'categoria': ?categoryId, 'estado': ?status?.cable},
    ).toString();
    final json = await _client.get('/$path');
    return [for (final e in _items(json['ejercicios'])) Exercise.fromJson(e)];
  }

  @override
  Future<List<Category>> categories(String clubId) async {
    final json = await _client.get(
      '/clubes/${Uri.encodeComponent(clubId)}/catalogo/categorias',
    );
    return [for (final c in _items(json['categorias'])) Category.fromJson(c)];
  }
}

List<Json> _items(Object? v) => [
  for (final e in (v as List? ?? const [])) (e as Map).cast<String, dynamic>(),
];
