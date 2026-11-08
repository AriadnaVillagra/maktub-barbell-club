import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/access/presentation/providers.dart';
import 'package:maktub_frontend/features/catalogo/domain/catalog_admin_repository.dart';
import 'package:maktub_frontend/features/catalogo/domain/catalog_repository.dart';
import 'package:maktub_frontend/features/catalogo/domain/exercise_draft.dart';
import 'package:maktub_frontend/features/catalogo/presentation/providers.dart';
import 'package:maktub_frontend/features/session/domain/session_manager.dart';
import 'package:maktub_frontend/features/session/presentation/providers.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../access/fakes.dart';

final _audit = Auditoria(creadoPor: 'u1', creadoEn: DateTime.utc(2026, 11, 7));

Category category(
  String id,
  String name, {
  String clubId = 'c1',
  CatalogStatus status = CatalogStatus.active,
}) => Category(
  id: id,
  clubId: clubId,
  name: name,
  status: status,
  auditoria: _audit,
);

Temporizador timer(
  String id,
  String name, {
  String clubId = 'c1',
  TipoTemporizador type = TipoTemporizador.countdown,
  int work = 90,
  int rest = 0,
  int rounds = 1,
  CatalogStatus status = CatalogStatus.active,
}) => Temporizador(
  id: id,
  clubId: clubId,
  nombre: name,
  tipo: type,
  trabajoSeg: work,
  descansoSeg: rest,
  rondas: rounds,
  estado: status,
  auditoria: _audit,
);

/// Keeps categories, timers and equipment in memory and answers like the API would.
class FakeCatalogAdminRepository
    implements CatalogRepository, CatalogAdminRepository {
  FakeCatalogAdminRepository({
    this.categoriesList = const [],
    this.timersList = const [],
    Equipo? team,
  }) : _team = team ?? Equipo.estandarDe('c1');

  List<Category> categoriesList;
  List<Temporizador> timersList;
  Equipo _team;
  final Set<String> inUse = {};
  final calls = <String>[];
  Equipo? savedTeam;

  @override
  Future<List<Category>> categories(String clubId) async => [...categoriesList];

  @override
  Future<List<Exercise>> exercises(
    String clubId, {
    String? categoryId,
    CatalogStatus? status,
  }) async => const [];

  @override
  Future<List<MuscleGroup>> muscleGroups(String clubId) async => const [];

  @override
  Future<List<MovementPattern>> patterns(String clubId) async => const [];

  @override
  Future<Exercise> createExercise(String clubId, ExerciseDraft draft) =>
      throw UnimplementedError();

  @override
  Future<Exercise> updateExercise(
    String clubId,
    String id,
    ExerciseDraft draft,
  ) => throw UnimplementedError();

  @override
  Future<Exercise> setExerciseStatus(
    String clubId,
    String id,
    CatalogStatus status,
  ) => throw UnimplementedError();

  @override
  Future<DeleteExerciseResult> deleteExercise(String clubId, String id) =>
      throw UnimplementedError();

  @override
  Future<Category> createCategory(String clubId, String name) async {
    calls.add('createCategory:$name');
    final c = category('new-${categoriesList.length}', name);
    categoriesList = [...categoriesList, c];
    return c;
  }

  @override
  Future<Category> renameCategory(String clubId, String id, String name) async {
    calls.add('renameCategory:$id:$name');
    final c = categoriesList.firstWhere((c) => c.id == id).copyWith(name: name);
    categoriesList = [for (final o in categoriesList) o.id == id ? c : o];
    return c;
  }

  @override
  Future<Category> setCategoryStatus(
    String clubId,
    String id,
    CatalogStatus status,
  ) async {
    calls.add('categoryStatus:$id:${status.cable}');
    final c = categoriesList
        .firstWhere((c) => c.id == id)
        .copyWith(status: status);
    categoriesList = [for (final o in categoriesList) o.id == id ? c : o];
    return c;
  }

  @override
  Future<RemovalOutcome> deleteCategory(String clubId, String id) async {
    calls.add('deleteCategory:$id');
    if (inUse.contains(id)) {
      await setCategoryStatus(clubId, id, CatalogStatus.archived);
      return RemovalOutcome.archived;
    }
    categoriesList = [
      for (final c in categoriesList)
        if (c.id != id) c,
    ];
    return RemovalOutcome.deleted;
  }

  @override
  Future<List<Temporizador>> timers(String clubId) async => [...timersList];

  @override
  Future<Temporizador> createTimer(String clubId, Temporizador draft) async {
    calls.add(
      'createTimer:${draft.nombre}:${draft.tipo.cable}:${draft.trabajoSeg}:${draft.descansoSeg}:${draft.rondas}',
    );
    final t = draft.copyWith();
    final saved = Temporizador(
      id: 'new-${timersList.length}',
      clubId: clubId,
      nombre: t.nombre,
      tipo: t.tipo,
      trabajoSeg: t.trabajoSeg,
      descansoSeg: t.descansoSeg,
      rondas: t.rondas,
      auditoria: _audit,
    );
    timersList = [...timersList, saved];
    return saved;
  }

  @override
  Future<Temporizador> updateTimer(String clubId, Temporizador timer) async {
    calls.add(
      'updateTimer:${timer.id}:${timer.nombre}:${timer.trabajoSeg}:${timer.estado.cable}',
    );
    timersList = [for (final o in timersList) o.id == timer.id ? timer : o];
    return timer;
  }

  @override
  Future<Temporizador> archiveTimer(String clubId, String id) async {
    calls.add('archiveTimer:$id');
    final t = timersList
        .firstWhere((t) => t.id == id)
        .copyWith(estado: CatalogStatus.archived);
    timersList = [for (final o in timersList) o.id == id ? t : o];
    return t;
  }

  @override
  Future<RemovalOutcome> deleteTimer(String clubId, String id) async {
    calls.add('deleteTimer:$id');
    timersList = [
      for (final t in timersList)
        if (t.id != id) t,
    ];
    return RemovalOutcome.deleted;
  }

  @override
  Future<Equipo> team(String clubId) async => _team;

  @override
  Future<Equipo> saveTeam(String clubId, Equipo team) async {
    calls.add('saveTeam');
    savedTeam = team;
    _team = team;
    return team;
  }
}

class _SignedIn extends SessionController {
  @override
  SessionStatus build() => SessionStatus.signedIn;
}

/// Mounts [page] for the club `c1` where the user holds [roles].
Future<void> pumpAdminPage(
  WidgetTester tester,
  Widget page,
  FakeCatalogAdminRepository repo, {
  Set<Rol> roles = const {Rol.coach, Rol.adminClub},
  bool isPlatformAdmin = false,
}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionControllerProvider.overrideWith(_SignedIn.new),
        meRepositoryProvider.overrideWithValue(
          FakeMeRepository(
            meWith([(club('c1', 'Gimnasio', TipoClub.club), roles)], isPlatformAdmin: isPlatformAdmin),
          ),
        ),
        catalogRepositoryProvider.overrideWithValue(repo),
        catalogAdminRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(theme: TemaMaktub.claro(), home: page),
    ),
  );
  await tester.pumpAndSettle();
}
