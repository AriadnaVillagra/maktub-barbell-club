import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/catalogo/domain/catalog_repository.dart';
import 'package:maktub_frontend/features/catalogo/domain/exercise_draft.dart';

Auditoria audit() =>
    Auditoria(creadoPor: 'u1', creadoEn: DateTime.utc(2026, 11, 7));

Exercise ex(
  String id,
  String name, {
  String clubId = 'c1',
  List<String> categories = const ['strength'],
  CatalogStatus status = CatalogStatus.active,
  List<MuscleShare> muscles = const [],
  String? patternId,
  List<Metric> metrics = const [Metric.loadPctRm, Metric.reps],
}) => Exercise(
  id: id,
  clubId: clubId,
  name: name,
  categoryIds: categories,
  metrics: metrics,
  defaultMetric: metrics.first,
  patternId: patternId,
  muscles: muscles,
  status: status,
  auditoria: audit(),
);

/// In-memory catalog that records writes and can be told to fail them.
class FakeCatalog implements CatalogRepository {
  FakeCatalog(this.items);

  final List<Exercise> items;
  final categoriesList = [
    Category(
      id: 'strength',
      clubId: clubPlataforma,
      name: 'Fuerza',
      auditoria: audit(),
    ),
    Category(
      id: 'accessory',
      clubId: clubPlataforma,
      name: 'Accesorio',
      auditoria: audit(),
    ),
  ];
  final groups = [
    MuscleGroup(
      id: 'quads',
      clubId: clubPlataforma,
      name: 'Cuádriceps',
      auditoria: audit(),
    ),
    MuscleGroup(
      id: 'glutes',
      clubId: clubPlataforma,
      name: 'Glúteos',
      auditoria: audit(),
    ),
  ];
  final patternsList = [
    MovementPattern(
      id: 'squat',
      clubId: clubPlataforma,
      name: 'Sentadilla',
      auditoria: audit(),
    ),
  ];

  final created = <ExerciseDraft>[];
  final updated = <(String, ExerciseDraft)>[];
  final statuses = <(String, CatalogStatus)>[];
  final deleted = <String>[];
  Object? failWrites;
  bool deleteArchives = false;

  @override
  Future<List<Exercise>> exercises(
    String clubId, {
    String? categoryId,
    CatalogStatus? status,
  }) async => [
    for (final e in items)
      if ((categoryId == null || e.categoryIds.contains(categoryId)) &&
          (status == null || e.status == status))
        e,
  ];

  @override
  Future<List<Category>> categories(String clubId) async => categoriesList;

  @override
  Future<List<MuscleGroup>> muscleGroups(String clubId) async => groups;

  @override
  Future<List<MovementPattern>> patterns(String clubId) async => patternsList;

  Exercise _from(
    String id,
    String clubId,
    ExerciseDraft d,
    CatalogStatus status,
  ) => Exercise.fromJson({
    ...d.toJson(),
    'id': id,
    'clubId': clubId,
    'estado': status.cable,
    'auditoria': audit().toJson(),
  });

  void _maybeFail() {
    final f = failWrites;
    if (f != null) throw f;
  }

  @override
  Future<Exercise> createExercise(String clubId, ExerciseDraft draft) async {
    _maybeFail();
    created.add(draft);
    final e = _from(
      'new-${created.length}',
      clubId,
      draft,
      CatalogStatus.active,
    );
    items.add(e);
    return e;
  }

  @override
  Future<Exercise> updateExercise(
    String clubId,
    String id,
    ExerciseDraft draft,
  ) async {
    _maybeFail();
    updated.add((id, draft));
    final i = items.indexWhere((e) => e.id == id);
    final e = _from(id, clubId, draft, items[i].status);
    items[i] = e;
    return e;
  }

  @override
  Future<Exercise> setExerciseStatus(
    String clubId,
    String id,
    CatalogStatus status,
  ) async {
    _maybeFail();
    statuses.add((id, status));
    final i = items.indexWhere((e) => e.id == id);
    return items[i] = items[i].copyWith(status: status);
  }

  @override
  Future<DeleteExerciseResult> deleteExercise(String clubId, String id) async {
    _maybeFail();
    deleted.add(id);
    final i = items.indexWhere((e) => e.id == id);
    if (deleteArchives) {
      items[i] = items[i].copyWith(status: CatalogStatus.archived);
      return DeleteExerciseResult(deleted: false, archived: items[i]);
    }
    items.removeAt(i);
    return const DeleteExerciseResult(deleted: true);
  }
}

const duplicateName = ErrorDeApi(
  'Ya hay un ejercicio con ese nombre.',
  estado: 409,
);
