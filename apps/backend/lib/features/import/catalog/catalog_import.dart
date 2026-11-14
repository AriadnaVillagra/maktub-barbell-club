import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/catalogo/create_timer/create_timer.dart';
import 'package:maktub_backend/features/catalogo/create_timer/create_timer_store.dart';
import 'package:maktub_backend/features/catalogo/write_exercise/write_exercise.dart';
import 'package:maktub_backend/features/catalogo/write_exercise/write_exercise_store.dart';
import 'package:maktub_backend/features/import/catalog/catalog_import_store.dart';
import 'package:maktub_backend/features/import/catalog/catalog_plan.dart';
import 'package:maktub_backend/features/import/catalog/catalog_sheets.dart';
import 'package:maktub_backend/features/import/import_report.dart';
import 'package:maktub_backend/features/import/import_run.dart';
import 'package:maktub_backend/features/wods/crear/crear.dart';
import 'package:maktub_backend/features/wods/crear/crear_store.dart';
import 'package:maktub_core/maktub_core.dart';

/// E8.2: Ejercicios, Temporizadores and WoDs into the club's catalog and WoD library. See
/// [planCatalogImport] for the rules. Writes only through the E2 catalog use cases ([WriteExercise],
/// [CreateTimer]) and the WoD library's [CreateWod].
class CatalogImport implements ImportStep {
  CatalogImport({
    required this._reads,
    required this._exerciseWrites,
    required this._timerWrites,
    required this._wodWrites,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final CatalogImportStore _reads;
  final WriteExerciseStore _exerciseWrites;
  final CreateTimerStore _timerWrites;
  final CreateWodStore _wodWrites;
  final DateTime Function() _now;

  @override
  String get name => 'catalogo';

  /// Reads the sheets and the club's catalog and decides what to do, without writing. Later steps call
  /// it to resolve sheet ids ([CatalogPlan.exerciseIdFor]) once the catalog is imported.
  Future<CatalogPlan> plan(ImportRun run) async {
    final sheets = CatalogSheets.read(
      exercises: run.sheets.read(CatalogSheetNames.exercises, columns: CatalogSheetNames.exerciseColumns),
      timers: run.sheets.read(CatalogSheetNames.timers, columns: CatalogSheetNames.timerColumns),
      wods: run.sheets.read(CatalogSheetNames.wods, columns: CatalogSheetNames.wodColumns),
    );
    final clubId = run.club.clubId;
    final visible = {clubPlataforma, clubId};
    final state = CatalogState(
      view: await _reads.view(visible),
      timers: await _reads.timers(visible),
      wods: await _reads.wods(clubId),
    );
    return planCatalogImport(sheets, state, clubId: clubId, adjustments: run.adjustments.exercises, now: _now());
  }

  @override
  Future<ImportReport> run(ImportRun run) async {
    final plan = await this.plan(run);
    if (!run.dryRun) await apply(run.club, plan);
    return plan.report;
  }

  /// Carries out [plan]: timers first (WoDs point at them), then exercises, then WoDs.
  Future<void> apply(ClubContext club, CatalogPlan plan) async {
    for (final t in plan.timersToCreate) {
      await CreateTimer(_timerWrites, now: _now, newId: () => t.id)(club, _body(t.toJson()));
    }
    for (final e in plan.exercisesToCreate) {
      await _exerciseUseCase(e.id).create(club, _body(e.toJson()));
      // Creating always leaves it active; an `inactivo` row is archived right after.
      if (!e.isActive) await _exerciseUseCase(e.id).setStatus(club, e.id, {'estado': e.status.cable});
    }
    for (final e in plan.exercisesToUpdate) {
      await _exerciseUseCase(e.id).update(club, e.id, _body(e.toJson()));
    }
    for (final w in plan.wodsToCreate) {
      await CreateWod(_wodWrites, now: _now, newId: () => w.id)(club, _body(w.toJson()));
    }
  }

  WriteExercise _exerciseUseCase(String id) =>
      WriteExercise(_exerciseWrites, const _NothingUsed(), newId: () => id, now: _now);

  /// The request body a client would send: the server's fields are set again by the use case.
  static Map<String, dynamic> _body(Map<String, dynamic> json) => {
    for (final e in json.entries)
      if (!const {'id', 'clubId', 'estado', 'auditoria'}.contains(e.key)) e.key: e.value,
  };
}

/// The import never deletes, so usage is never asked.
class _NothingUsed implements ExerciseUsage {
  const _NothingUsed();

  @override
  Future<bool> isUsed(String clubId, String exerciseId) async => false;
}
