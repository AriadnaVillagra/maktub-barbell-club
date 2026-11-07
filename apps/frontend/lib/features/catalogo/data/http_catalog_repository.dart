import 'package:maktub_core/maktub_core.dart';

import '../../../core/red/cliente_api.dart';
import '../domain/catalog_repository.dart';
import '../domain/exercise_draft.dart';

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

  @override
  Future<List<MuscleGroup>> muscleGroups(String clubId) async {
    final json = await _client.get('/${_catalog(clubId, 'grupos')}');
    return [for (final g in _items(json['grupos'])) MuscleGroup.fromJson(g)];
  }

  @override
  Future<List<MovementPattern>> patterns(String clubId) async {
    final json = await _client.get('/${_catalog(clubId, 'patrones')}');
    return [
      for (final p in _items(json['patrones'])) MovementPattern.fromJson(p),
    ];
  }

  @override
  Future<Exercise> createExercise(String clubId, ExerciseDraft draft) async =>
      Exercise.fromJson(
        await _client.post(
          '/${_catalog(clubId, 'ejercicios')}',
          cuerpo: draft.toJson(),
        ),
      );

  @override
  Future<Exercise> updateExercise(
    String clubId,
    String id,
    ExerciseDraft draft,
  ) async => Exercise.fromJson(
    await _client.put('/${_catalog(clubId, 'ejercicios', id)}', draft.toJson()),
  );

  @override
  Future<Exercise> setExerciseStatus(
    String clubId,
    String id,
    CatalogStatus status,
  ) async => Exercise.fromJson(
    await _client.patch('/${_catalog(clubId, 'ejercicios', id)}', {
      'estado': status.cable,
    }),
  );

  @override
  Future<DeleteExerciseResult> deleteExercise(String clubId, String id) async {
    final json = await _client.delete('/${_catalog(clubId, 'ejercicios', id)}');
    final archived = json['ejercicio'];
    return DeleteExerciseResult(
      deleted: json['resultado'] == 'borrado',
      archived: archived is Map
          ? Exercise.fromJson(archived.cast<String, dynamic>())
          : null,
    );
  }
}

String _catalog(String clubId, String kind, [String? id]) =>
    Uri(pathSegments: ['clubes', clubId, 'catalogo', kind, ?id]).toString();

List<Json> _items(Object? v) => [
  for (final e in (v as List? ?? const [])) (e as Map).cast<String, dynamic>(),
];
