// Importer of the old spreadsheet (E8, design.md 3.5): `cd apps/backend && dart run tool/importar.dart`.
//
// Reads the CSVs exported in E8.1 and loads them into a club, step by step. Without `--aplicar` it is a
// dry run: it reads MONGO_URL and reports what it would do, writing nothing. Every step is idempotent.
//
//   --carpeta <dir>   folder with the CSVs (default ../../docs/planillas/csv/apps-script, never in git)
//   --club <id>       club to import into (default: the club named "Maktub")
//   --solo <a,b>      only these steps (default: all, in order)
//   --ajustes <file>  decisions about the data (default tool/importar/ajustes.json)
//   --aplicar         write; without it nothing is written
//   --detalle         also list what is already there
//
// Exit code 1 when a step reports rows it could not import.
import 'dart:io';

import 'package:maktub_backend/features/acceso/club_context/club_context_store.dart';
import 'package:maktub_backend/features/catalogo/create_timer/create_timer_store.dart';
import 'package:maktub_backend/features/catalogo/write_exercise/write_exercise_store.dart';
import 'package:maktub_backend/features/asignaciones/crear/crear_store.dart';
import 'package:maktub_backend/features/import/adjustments.dart';
import 'package:maktub_backend/features/import/assignments/assignment_import.dart';
import 'package:maktub_backend/features/import/assignments/assignment_import_store.dart';
import 'package:maktub_backend/features/import/athletes/athlete_import.dart';
import 'package:maktub_backend/features/import/athletes/athlete_import_store.dart';
import 'package:maktub_backend/features/import/catalog/catalog_import.dart';
import 'package:maktub_backend/features/import/catalog/catalog_import_store.dart';
import 'package:maktub_backend/features/import/history/history_import.dart';
import 'package:maktub_backend/features/import/history/history_import_store.dart';
import 'package:maktub_backend/features/import/history/history_plan.dart';
import 'package:maktub_backend/features/import/import_run.dart';
import 'package:maktub_backend/features/import/plans/plan_import.dart';
import 'package:maktub_backend/features/import/plans/plan_import_store.dart';
import 'package:maktub_backend/features/import/sheets.dart';
import 'package:maktub_backend/features/kilajes/fijar_kilaje/fijar_kilaje_store.dart';
import 'package:maktub_backend/features/plan/crear/crear_store.dart';
import 'package:maktub_backend/features/plan/guardar/guardar_store.dart';
import 'package:maktub_backend/features/plan/publicar/publicar_store.dart';
import 'package:maktub_backend/features/referencias/registrar_rm/registrar_rm_store.dart';
import 'package:maktub_backend/features/sesion/open_session/open_session_store.dart';
import 'package:maktub_backend/features/sesion/record_block_time/record_block_time_store.dart';
import 'package:maktub_backend/features/sesion/record_set/record_set_store.dart';
import 'package:maktub_backend/features/wods/crear/crear_store.dart';
import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// The steps in the order they run.
List<ImportStep> _steps(Db db) {
  final catalog = CatalogImport(
    reads: MongoCatalogImportStore(db),
    exerciseWrites: MongoWriteExerciseStore(db),
    timerWrites: MongoCreateTimerStore(db),
    wodWrites: MongoCreateWodStore(db),
  );
  final athletes = AthleteImport(
    reads: MongoAthleteImportStore(db),
    exercises: (run) async => (await catalog.plan(run)).exerciseIdFor,
    rmWrites: MongoRegisterRmStore(db),
    weightWrites: MongoSetFixedWeightStore(db),
  );
  final plans = PlanImport(
    catalog: catalog,
    reads: MongoPlanImportStore(db),
    creates: MongoCreatePlanStore(db),
    saves: MongoSavePlanStore(db),
    publishes: MongoPublishPlanStore(db),
  );
  final assignments = AssignmentImport(
    reads: MongoAssignmentImportStore(db),
    writes: MongoCreateAssignmentStore(db),
    derived: (run) async {
      final historic = (await plans.plan(run)).historic;
      final athletePlan = await athletes.plan(run);
      return historicAssignments(historic, athletePlan.athleteIdFor);
    },
  );
  return [
    catalog,
    athletes,
    plans,
    assignments,
    HistoryImport(
      sources: (run) async {
        final catalogPlan = await catalog.plan(run);
        final athletePlan = await athletes.plan(run);
        final planPlan = await plans.plan(run);
        final assignmentPlan = await assignments.plan(run);
        return HistorySources(
          exerciseIdFor: catalogPlan.exerciseIdFor,
          athleteIdFor: athletePlan.athleteIdFor,
          sheetAthletes: HistoryImport.sheetAthletes(run),
          plans: planPlan,
          pending: [
            if (!catalogPlan.isEmpty) catalog.name,
            if (athletePlan.rmsToCreate.isNotEmpty || athletePlan.fixedWeightsToCreate.isNotEmpty) athletes.name,
            if (!planPlan.isEmpty || planPlan.catalogPending) plans.name,
            if (!assignmentPlan.isEmpty) assignments.name,
          ],
        );
      },
      reads: MongoHistoryImportStore(db),
      sessionWrites: MongoOpenSessionStore(db),
      setWrites: MongoRecordSetStore(db),
      timeWrites: MongoRecordBlockTimeStore(db),
    ),
  ];
}

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  final db = await abrirMongo();
  var failed = false;
  try {
    final clubId = options.club ?? await _maktubClubId(db);
    final type = await MongoClubContextStore(db).clubType(clubId);
    if (type == null) throw StateError('No existe el club $clubId.');
    stdout.writeln(
      'Base: ${db.databaseName} · club: $clubId · ${options.apply ? 'APLICANDO' : 'simulación (sin --aplicar)'}',
    );
    final run = ImportRun(
      club: importClubContext(clubId, type),
      sheets: SheetDirectory(options.folder),
      adjustments: ImportAdjustments.fromFile(options.adjustments),
      dryRun: !options.apply,
    );
    final steps = _steps(db).where((s) => options.only.isEmpty || options.only.contains(s.name)).toList();
    final unknown = options.only.difference({for (final s in _steps(db)) s.name});
    if (unknown.isNotEmpty) throw ArgumentError('Pasos desconocidos: ${unknown.join(', ')}.');
    for (final step in steps) {
      final report = await step.run(run);
      report.writeTo(stdout, dryRun: run.dryRun, verbose: options.verbose);
      failed = failed || report.problems.isNotEmpty;
    }
  } finally {
    await db.close();
  }
  if (failed) exitCode = 1;
}

Future<String> _maktubClubId(Db db) async {
  final club = await db
      .collection(Colecciones.clubes)
      .findOne(where.eq('tipo', TipoClub.club.cable).eq('nombre', 'Maktub'));
  if (club == null) throw StateError('No hay club "Maktub": pasá --club <id> o corré antes tool/alta.dart.');
  return '${club['_id']}';
}

class _Options {
  _Options({
    required this.folder,
    required this.club,
    required this.only,
    required this.adjustments,
    required this.apply,
    required this.verbose,
  });

  factory _Options.parse(List<String> args) {
    String? value(String name) {
      final i = args.indexOf(name);
      if (i < 0) return null;
      if (i + 1 >= args.length) throw ArgumentError('Falta el valor de $name.');
      return args[i + 1];
    }

    return _Options(
      folder: value('--carpeta') ?? '../../docs/planillas/csv/apps-script',
      club: value('--club'),
      only: {...?value('--solo')?.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty)},
      adjustments: value('--ajustes') ?? 'tool/importar/ajustes.json',
      apply: args.contains('--aplicar'),
      verbose: args.contains('--detalle'),
    );
  }

  final String folder;
  final String? club;
  final Set<String> only;
  final String adjustments;
  final bool apply;
  final bool verbose;
}
