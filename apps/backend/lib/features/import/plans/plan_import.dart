import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/import/catalog/catalog_import.dart';
import 'package:maktub_backend/features/import/catalog/catalog_sheets.dart';
import 'package:maktub_backend/features/import/import_report.dart';
import 'package:maktub_backend/features/import/import_run.dart';
import 'package:maktub_backend/features/import/plans/plan_import_plan.dart';
import 'package:maktub_backend/features/import/plans/plan_import_store.dart';
import 'package:maktub_backend/features/import/plans/plan_sheets.dart';
import 'package:maktub_backend/features/plan/crear/crear.dart';
import 'package:maktub_backend/features/plan/crear/crear_store.dart';
import 'package:maktub_backend/features/plan/guardar/guardar.dart';
import 'package:maktub_backend/features/plan/guardar/guardar_store.dart';
import 'package:maktub_backend/features/plan/publicar/publicar.dart';
import 'package:maktub_backend/features/plan/publicar/publicar_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';

/// E8.4: Planes, PlanModelos, PlanDias and PlanEjercicios into the club's plans, with October 2026 corrected
/// (M1-D4, `plans.pctCorrections` in the adjustments). See [planPlanImport] for the rules. Writes only through
/// the plan use cases: [CreatePlan], [SavePlan] (the whole plan in one write) and [PublishPlan], which only
/// accepts a complete plan; the others stay as drafts and the report says why.
class PlanImport implements ImportStep {
  PlanImport({
    required this._catalog,
    required this._reads,
    required this._creates,
    required this._saves,
    required this._publishes,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final CatalogImport _catalog;
  final PlanImportStore _reads;
  final CreatePlanStore _creates;
  final SavePlanStore _saves;
  final PublishPlanStore _publishes;
  final DateTime Function() _now;

  @override
  String get name => 'planes';

  /// Reads the sheets, the catalog and the club's plans and decides what to do, without writing. The history
  /// import (E8.5) calls it for [PlanImportPlan.locate].
  Future<PlanImportPlan> plan(ImportRun run) async {
    final clubId = run.club.clubId;
    final catalogPlan = await _catalog.plan(run);
    final exercises = {for (final e in await _reads.exercises(clubId)) e.id: e};
    // The catalog as the catalog step leaves it, so a dry run on an empty club already sees its exercises.
    for (final e in [...catalogPlan.exercisesToCreate, ...catalogPlan.exercisesToUpdate]) {
      exercises[e.id] = e;
    }
    final sheetExercises = CatalogSheets.read(
      exercises: run.sheets.read(CatalogSheetNames.exercises, columns: CatalogSheetNames.exerciseColumns),
      timers: run.sheets.read(CatalogSheetNames.timers, columns: CatalogSheetNames.timerColumns),
      wods: run.sheets.read(CatalogSheetNames.wods, columns: CatalogSheetNames.wodColumns),
    ).exercises;
    final sheets = PlanSheets.read(
      plans: run.sheets.read(PlanSheetNames.plans, columns: PlanSheetNames.planColumns),
      weekModels: run.sheets.read(PlanSheetNames.weekModels, columns: PlanSheetNames.weekModelColumns),
      days: run.sheets.read(PlanSheetNames.days, columns: PlanSheetNames.dayColumns),
      sets: run.sheets.read(PlanSheetNames.sets, columns: PlanSheetNames.setColumns),
      wods: run.sheets.read(PlanSheetNames.wods, columns: PlanSheetNames.wodColumns),
    );
    final existing = await _reads.plans(clubId, {for (final p in sheets.plans) importedId(clubId, p.id)});
    final plan = planPlanImport(
      sheets,
      PlanCatalog(
        exerciseIdFor: catalogPlan.exerciseIdFor,
        timerIdFor: (id) => catalogPlan.timerIds[id],
        exercises: exercises,
        sheetExercises: sheetExercises,
      ),
      clubId: clubId,
      existing: existing,
      now: _now(),
      corrections: planAdjustments(run.adjustments.raw),
      fills: planPctFills(run.adjustments.raw),
    );
    if (!catalogPlan.isEmpty) {
      plan.catalogPending = true;
      (run.dryRun ? plan.report.notes : plan.report.problems).add(
        'El catálogo de la planilla todavía no está importado: ${run.dryRun ? 'esto supone que el paso '
                  '"catalogo" se aplica antes' : 'no se escribe ningún plan; corré antes el paso "catalogo"'}.',
      );
    }
    return plan;
  }

  @override
  Future<ImportReport> run(ImportRun run) async {
    final plan = await this.plan(run);
    if (!run.dryRun && !plan.catalogPending) {
      await apply(run.club, plan);
    }
    return plan.report;
  }

  /// Carries out [plan]. A plan the use cases reject is reported and the others go on.
  Future<void> apply(ClubContext club, PlanImportPlan plan) async {
    for (final p in plan.toCreate) {
      try {
        await CreatePlan(_creates, newId: () => p.plan.id, now: _now)(club, {
          'nombre': p.plan.name,
          'tipo': p.plan.type.cable,
        });
        await SavePlan(_saves, now: _now)(club, p.plan.id, p.plan.toJson());
        if (p.publishable) await PublishPlan(_publishes, now: _now)(club, p.plan.id);
      } on ErrorDeSolicitud catch (e) {
        plan.report.problems.add('plan ${p.sheetId}: no se pudo escribir (${e.estado}): ${e.mensaje} ${e.extra}');
      }
    }
    for (final p in plan.toUpdate) {
      try {
        await SavePlan(_saves, now: _now)(club, p.plan.id, p.plan.toJson());
        if (p.publishable) await PublishPlan(_publishes, now: _now)(club, p.plan.id);
      } on ErrorDeSolicitud catch (e) {
        plan.report.problems.add('plan ${p.sheetId}: no se pudo guardar (${e.estado}): ${e.mensaje} ${e.extra}');
      }
    }
    for (final id in plan.toPublish) {
      try {
        await PublishPlan(_publishes, now: _now)(club, id);
      } on ErrorDeSolicitud catch (e) {
        plan.report.problems.add('plan $id: no se pudo publicar (${e.estado}): ${e.mensaje} ${e.extra}');
      }
    }
  }
}

/// The plan section of `tool/importar/ajustes.json`: `{"plans": {"pctCorrections": [{"plan", "from", "to"}]}}`.
List<PctCorrection> planAdjustments(Map<String, dynamic> raw) => [
  for (final c in ((raw['plans'] as Map?)?['pctCorrections'] as List? ?? const []))
    PctCorrection.fromJson((c as Map).cast<String, dynamic>()),
];

/// `{"plans": {"pctFills": [{"plan", "variante", "dia", "bloque", "grupo"?, "orden"?, "ejercicio", "serie", "pct"}]}}`:
/// the percentages the sheet leaves empty, one per PlanEjercicios row. `pct` null is a value still to supply.
List<PctFill> planPctFills(Map<String, dynamic> raw) => [
  for (final f in ((raw['plans'] as Map?)?['pctFills'] as List? ?? const []))
    PctFill.fromJson((f as Map).cast<String, dynamic>()),
];
