import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/asignaciones/crear/crear.dart';
import 'package:maktub_backend/features/asignaciones/crear/crear_store.dart';
import 'package:maktub_backend/features/import/catalog/catalog_sheets.dart';
import 'package:maktub_backend/features/import/grid/grid_import_store.dart';
import 'package:maktub_backend/features/import/grid/grid_plan.dart';
import 'package:maktub_backend/features/import/grid/grid_sheet.dart';
import 'package:maktub_backend/features/import/import_report.dart';
import 'package:maktub_backend/features/import/import_run.dart';
import 'package:maktub_backend/features/plan/crear/crear.dart';
import 'package:maktub_backend/features/plan/crear/crear_store.dart';
import 'package:maktub_backend/features/plan/guardar/guardar.dart';
import 'package:maktub_backend/features/plan/guardar/guardar_store.dart';
import 'package:maktub_backend/features/plan/publicar/publicar.dart';
import 'package:maktub_backend/features/plan/publicar/publicar_store.dart';
import 'package:maktub_backend/features/sesion/live_broadcast.dart';
import 'package:maktub_backend/features/sesion/open_session/open_session.dart';
import 'package:maktub_backend/features/sesion/open_session/open_session_store.dart';
import 'package:maktub_backend/features/sesion/record_set/record_set.dart';
import 'package:maktub_backend/features/sesion/record_set/record_set_store.dart';
import 'package:maktub_backend/infraestructura/http.dart';

/// What the earlier steps resolve for the grid: E8.2's exercise ids and the old sheet's exercise names.
class GridSources {
  const GridSources({required this.exerciseIdFor, this.sheetNames = const {}, this.pending = const []});

  /// Sheet exercise id → app id (`CatalogPlan.exerciseIdFor`).
  final String? Function(String sheetId) exerciseIdFor;

  /// [plainName] of an Ejercicios name → its sheet id.
  final Map<String, String> sheetNames;

  /// The earlier steps that still have work to do. While there is any, nothing is written.
  final List<String> pending;
}

/// E8.7: April to July 2026, which Registro does not have. Builds the plan of the April planning grid
/// (`planificacion/ABR_2026.csv`) and loads its sessions of those four months with the kilos the app proposes,
/// marked as **estimated** so they can be corrected later. See [planGridImport] for the rules and `planningGrid` in
/// the adjustments for the decisions. Writes only through the use cases: [CreatePlan], [SavePlan] and [PublishPlan]
/// (history mode), [CreateAssignment] (history mode, already ended), [OpenSession] (history mode) and [RecordSet] in
/// estimate mode, the only writer allowed to mark a set estimated.
class GridImport implements ImportStep {
  GridImport({
    required this._sources,
    required this._gridCsv,
    required this._reads,
    required this._planCreates,
    required this._planSaves,
    required this._planPublishes,
    required this._assignmentWrites,
    required this._sessionWrites,
    required this._setWrites,
    LiveBroadcast? broadcast,
    DateTime Function()? now,
  }) : _broadcast = broadcast ?? MemoryLiveBroadcast(),
       _now = now ?? DateTime.now;

  final Future<GridSources> Function(ImportRun run) _sources;

  /// The CSV text of the planning grid named [sheet] (`ABR_2026`).
  final String Function(String sheet) _gridCsv;
  final GridImportStore _reads;
  final CreatePlanStore _planCreates;
  final SavePlanStore _planSaves;
  final PublishPlanStore _planPublishes;
  final CreateAssignmentStore _assignmentWrites;
  final OpenSessionStore _sessionWrites;
  final RecordSetStore _setWrites;
  final LiveBroadcast _broadcast;
  final DateTime Function() _now;

  @override
  String get name => 'abril';

  /// The names of Ejercicios ([plainName]) → their sheet id, for [GridSources.sheetNames]. A name two rows share is
  /// left out.
  static Map<String, String> sheetNames(ImportRun run) {
    final ids = <String, Set<String>>{};
    for (final row in run.sheets.read(CatalogSheetNames.exercises, columns: CatalogSheetNames.exerciseColumns).rows) {
      if (row['id'].isNotEmpty && row['nombre'].isNotEmpty) ids.putIfAbsent(plainName(row['nombre']), () => {}).add(row['id']);
    }
    return {
      for (final e in ids.entries)
        if (e.value.length == 1) e.key: e.value.single,
    };
  }

  /// Reads the grid and the club and decides what to do, without writing. Null without `planningGrid` in the
  /// adjustments.
  Future<GridImportPlan?> plan(ImportRun run) async {
    final adj = GridAdjustments.fromRaw(run.adjustments.raw);
    if (adj == null) return null;
    final clubId = run.club.clubId;
    final grid = PlanningGrid.parse(_gridCsv(adj.sheet));
    final sources = await _sources(run);
    final groups = await _reads.groups(clubId);
    final memberIds = {for (final g in groups) ...g.memberIds};
    final assignmentId = gridAssignmentId(clubId, adj);
    final sessions = await _reads.sessions(clubId, assignmentId);
    final state = GridState(
      plan: await _reads.plan(clubId, importedId(clubId, adj.planKey)),
      assignment: await _reads.assignment(clubId, assignmentId),
      groups: groups,
      athletes: await _reads.athletes(clubId, memberIds),
      sessions: sessions,
      records: await _reads.records(clubId, {for (final s in sessions) s.id}),
      references: await _reads.references(clubId, memberIds),
      factors: await _reads.workFactors(clubId, memberIds),
      fixedWeights: await _reads.fixedWeights(clubId, memberIds),
      equipment: await _reads.equipment(clubId),
    );
    final plan = planGridImport(
      grid,
      adj,
      GridCatalog(
        exerciseIdFor: sources.exerciseIdFor,
        exercises: await _reads.exercises(clubId),
        sheetNames: sources.sheetNames,
      ),
      state,
      clubId: clubId,
      now: _now(),
    );
    if (sources.pending.isNotEmpty) {
      plan.pending = true;
      final steps = sources.pending.map((s) => '"$s"').join(', ');
      (run.dryRun ? plan.report.notes : plan.report.problems).add(
        run.dryRun
            ? 'Los pasos $steps tienen cambios sin aplicar: esto muestra la grilla contra lo que hay hoy.'
            : 'Los pasos $steps tienen cambios sin aplicar: no se escribe nada de la grilla; corrélos antes.',
      );
    }
    return plan;
  }

  @override
  Future<ImportReport> run(ImportRun run) async {
    final plan = await this.plan(run);
    if (plan == null) {
      return ImportReport('Abril 2026 (series estimadas)')..notes.add('No hay "planningGrid" en los ajustes.');
    }
    if (run.dryRun) {
      _describe(plan);
    } else {
      await apply(run.club, plan);
    }
    return plan.report;
  }

  void _describe(GridImportPlan plan) {
    final report = plan.report;
    for (final s in plan.sessions) {
      final there = s.sets.where((p) => p.stored != null).length;
      final line =
          '${s.label}: ${s.sets.length} series estimadas'
          '${there > 0 ? ' ($there ya cargadas: se reescriben si cambian)' : ''}'
          '${s.kept > 0 ? ', ${s.kept} corregidas en la app (no se tocan)' : ''}.';
      if (s.existing == null) {
        report.created.add(line);
      } else if (there == s.sets.length) {
        report.unchanged.add(line);
      } else {
        report.updated.add(line);
      }
    }
    if ((plan.blocked || plan.pending) && plan.sessions.isNotEmpty) {
      report.notes.add('Con lo de arriba sin resolver, al aplicar no se cargaría ninguna sesión.');
    }
  }

  /// Carries out [plan]: the plan, then the assignment, then the sessions. A session or set the use cases reject is
  /// reported and the others go on.
  Future<void> apply(ClubContext club, GridImportPlan plan) async {
    final report = plan.report;
    final now = _now;
    final p = plan.plan;
    if (plan.pending) return;
    try {
      if (plan.createPlan) {
        await CreatePlan(_planCreates, newId: () => p.id, now: now, allowHistory: true)(club, {
          'nombre': p.name,
          'tipo': p.type.cable,
        });
        await SavePlan(_planSaves, now: now)(club, p.id, p.toJson());
      }
      if ((plan.createPlan || plan.publishPlan) && plan.publishable) {
        await PublishPlan(_planPublishes, now: now, history: true, askAthleteKg: false)(club, p.id);
      }
    } on ErrorDeSolicitud catch (e) {
      report.problems.add('plan "${p.name}": no se pudo escribir (${e.estado}): ${e.mensaje} ${e.extra}');
      return;
    }
    if (plan.blocked) return;
    final assignmentBody = plan.assignmentBody;
    if (assignmentBody != null) {
      try {
        await CreateAssignment(_assignmentWrites, newId: () => plan.assignmentId!, now: now, history: true)(
          club,
          assignmentBody,
        );
      } on ErrorDeSolicitud catch (e) {
        report.problems.add('asignación de "${p.name}": no se pudo escribir (${e.estado}): ${e.mensaje}');
        return;
      }
    }
    var written = 0, same = 0;
    for (final s in plan.sessions) {
      final String sessionId;
      try {
        final opened = await OpenSession(_sessionWrites, _broadcast, newId: () => s.id, now: now, history: true)(
          club,
          s.openBody,
        );
        sessionId = opened.session.id;
      } on ErrorDeSolicitud catch (e) {
        report.problems.add(
          '${s.label}: no se pudo abrir la sesión (${e.estado}): ${e.mensaje}; sus ${s.sets.length} series no se cargan.',
        );
        continue;
      }
      var sessionWritten = 0;
      for (final set in s.sets) {
        try {
          final record = await RecordSet(_setWrites, _broadcast, newId: () => set.id, now: now, estimates: true)(
            club,
            sessionId,
            set.body,
          );
          if (set.stored != null && set.stored!.sequence == record.sequence) {
            same++;
          } else {
            sessionWritten++;
          }
          if (record.kg != set.kg) {
            report.notes.add('${s.label}: la app guardó ${record.kg} kg y se esperaban ${set.kg} kg (${set.body}).');
          }
        } on ErrorDeSolicitud catch (e) {
          report.problems.add('${s.label}: una serie no se pudo escribir (${e.estado}): ${e.mensaje} (${set.body}).');
        }
      }
      written += sessionWritten;
      final line =
          '${s.label}: $sessionWritten series estimadas escritas, ${s.sets.length - sessionWritten} sin cambios'
          '${s.kept > 0 ? ', ${s.kept} corregidas en la app (no se tocan)' : ''}.';
      if (s.existing == null) {
        report.created.add(line);
      } else if (sessionWritten > 0) {
        report.updated.add(line);
      } else {
        report.unchanged.add(line);
      }
    }
    report.notes.add('Series estimadas: $written escritas, $same sin cambios.');
  }
}
