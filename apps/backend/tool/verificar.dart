// Verification of the migration (E8.6): `cd apps/backend && dart run tool/verificar.dart`.
//
// Reads only; never writes. Uses MONGO_URL like the importer. Three parts:
//
//   1. Cantidades: every importer step in a dry run. With everything loaded, no step has anything left to create
//      or update, and every Registro row is either a loaded set or a skipped row with its reason.
//   2. Invariante: `rm × pctReal ≈ kg` on every set of the club that has the three, within half the gap between
//      the loadable weights around the expected kilos (decided by Ari on 2026-11-16).
//   3. Muestra: Registro rows picked at random, each next to what the app stored, for Ari to check against the
//      spreadsheet by line number.
//
//   --carpeta, --planificacion, --club, --ajustes   as in tool/importar.dart
//   --muestra <n>    rows in the sample (default 20)
//   --semilla <n>    seed of the sample, to repeat the same one (default: today's date)
//
// Exit code 1 when something is left to load, a set breaks the invariant, or a sample row differs.
import 'dart:io';
import 'dart:math';

import 'package:maktub_backend/features/acceso/club_context/club_context_store.dart';
import 'package:maktub_backend/features/import/adjustments.dart';
import 'package:maktub_backend/features/import/history/history_import.dart';
import 'package:maktub_backend/features/import/history/history_plan.dart';
import 'package:maktub_backend/features/import/history/history_sheets.dart';
import 'package:maktub_backend/features/import/import_run.dart';
import 'package:maktub_backend/features/import/sheets.dart';
import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';

import 'importar.dart' show importSteps, maktubClubId;

Future<void> main(List<String> args) async {
  String? value(String name) {
    final i = args.indexOf(name);
    if (i < 0) return null;
    if (i + 1 >= args.length) throw ArgumentError('Falta el valor de $name.');
    return args[i + 1];
  }

  final folder = value('--carpeta') ?? '../../docs/planillas/csv/apps-script';
  final planning = value('--planificacion') ?? '../../docs/planillas/csv/planificacion';
  final sampleSize = int.parse(value('--muestra') ?? '20');
  final now = DateTime.now();
  final seed = int.parse(value('--semilla') ?? '${now.year * 10000 + now.month * 100 + now.day}');

  final db = await abrirMongo();
  var failed = false;
  try {
    final clubId = value('--club') ?? await maktubClubId(db);
    final type = await MongoClubContextStore(db).clubType(clubId);
    if (type == null) throw StateError('No existe el club $clubId.');
    stdout.writeln('Base: ${db.databaseName} · club: $clubId · solo lectura');
    final run = ImportRun(
      club: importClubContext(clubId, type),
      sheets: SheetDirectory(folder),
      adjustments: ImportAdjustments.fromFile(value('--ajustes') ?? 'tool/importar/ajustes.json'),
      dryRun: true,
    );
    final steps = importSteps(db, planningFolder: planning);

    failed = !await _counts(steps, run) | failed;
    final history = steps.whereType<HistoryImport>().single;
    final plan = await history.plan(run);
    failed = !_registro(plan, run) | failed;
    failed = !await _invariant(db, clubId) | failed;
    failed = !_sample(plan, run, size: sampleSize, seed: seed) | failed;
  } finally {
    await db.close();
  }
  stdout.writeln(failed ? '\n✗ Hay diferencias para revisar (arriba).' : '\n✓ Sin diferencias.');
  if (failed) exitCode = 1;
}

/// Part 1: each step in a dry run. True when no step has anything left to create or update.
Future<bool> _counts(List<ImportStep> steps, ImportRun run) async {
  stdout.writeln('\n## 1. Cantidades (el importador en simulación)');
  var ok = true;
  for (final step in steps) {
    final report = await step.run(run);
    final left = report.created.length + report.updated.length;
    ok = ok && left == 0;
    stdout.writeln('${left == 0 ? '✓' : '✗'} ${report.summary(dryRun: true)}');
    for (final (title, lines) in [
      ('Falta cargar', [...report.created, ...report.updated]),
      // What was changed in the app wins over the sheet and is never overwritten (Ari, 2026-11-19): listed, not a
      // failure.
      ('Difiere de la planilla; queda lo de la app', report.differing),
      ('Filas no importadas', report.problems),
      ('Avisos', report.notes),
    ]) {
      if (lines.isEmpty) continue;
      stdout.writeln('    $title (${lines.length}):');
      for (final l in lines) {
        stdout.writeln('      - $l');
      }
    }
  }
  return ok;
}

/// Part 1, Registro: every row is a loaded set or a skipped row (listed by the history step with its reason).
bool _registro(HistoryPlan plan, ImportRun run) {
  final rows = run.sheets.read(HistorySheetNames.records, columns: HistorySheetNames.recordColumns).rows.length;
  var loaded = 0;
  var missing = 0;
  for (final session in plan.sessions) {
    for (final set in session.sets) {
      session.stored[set.position] == null ? missing++ : loaded++;
    }
  }
  final skipped = rows - loaded - missing;
  stdout.writeln(
    '\n${missing == 0 ? '✓' : '✗'} Registro: $rows filas = $loaded series cargadas + $missing sin cargar + '
    '$skipped saltadas o repetidas (con su motivo en "Historial", arriba).',
  );
  return missing == 0;
}

/// Part 2: `referenceValue × pctReal / 100 ≈ kg` on every set of the club that has the three.
Future<bool> _invariant(Db db, String clubId) async {
  stdout.writeln('\n## 2. Invariante rm × % ≈ kg');
  final equipmentDoc = await db.collection(Colecciones.equipos).findOne({'_id': clubId});
  final equipment = equipmentDoc == null ? Equipo.estandar : Equipo.fromJson(desdeDocumento(equipmentDoc));
  final loadable = [...equipment.cargables]..sort();
  final docs = await db.collection(Colecciones.registros).find({
    'clubId': clubId,
    'kilos': {r'$ne': null},
    'referenciaValor': {r'$ne': null},
    'pctReal': {r'$ne': null},
  }).toList();
  final dates = {
    for (final s in await db.collection(Colecciones.sesiones).find({'clubId': clubId}).toList())
      '${s['_id']}': '${s['fecha']}',
  };
  final broken = <String>[];
  var estimated = 0;
  for (final d in docs) {
    final kg = (d['kilos'] as num).toDouble();
    final expected = (d['referenciaValor'] as num).toDouble() * (d['pctReal'] as num).toDouble() / 100;
    if (d['estimada'] == true) estimated++;
    if ((kg - expected).abs() <= _tolerance(expected, loadable) + 0.01) continue;
    broken.add(
      '${dates['${d['sesionId']}'] ?? '?'} · ${d['ejercicioNombre']} · atleta ${d['atletaId']} · '
      '${_kg(kg)} kg, esperado ${_kg(expected)} kg (rm ${_kg((d['referenciaValor'] as num).toDouble())} × '
      '${d['pctReal']} %)${d['estimada'] == true ? ' · estimada' : ''}${d['kilosManual'] == true ? ' · kilos a mano' : ''}',
    );
  }
  broken.sort();
  stdout.writeln(
    '${broken.isEmpty ? '✓' : '✗'} ${docs.length} series con rm, % y kilos ($estimated estimadas): '
    '${docs.length - broken.length} dentro de la tolerancia, ${broken.length} fuera.',
  );
  for (final b in broken) {
    stdout.writeln('    - $b');
  }
  return broken.isEmpty;
}

/// Half the gap between the loadable weights just below and just above [expected]: what rounding to the nearest
/// loadable can move it. Below the lightest loadable (an empty bar is heavier than asked) it is the distance up to it.
double _tolerance(double expected, List<double> loadable) {
  if (loadable.isEmpty) return 0;
  double? below;
  double? above;
  for (final w in loadable) {
    if (w <= expected) below = w;
    if (w >= expected) {
      above = w;
      break;
    }
  }
  if (below == null) return above! - expected;
  if (above == null) return expected - below;
  return (above - below) / 2;
}

/// Part 3: [size] Registro rows that were loaded, at random with [seed], each next to what the app stored.
bool _sample(HistoryPlan plan, ImportRun run, {required int size, required int seed}) {
  stdout.writeln('\n## 3. Muestra para revisar a mano (semilla $seed)');
  stdout.writeln('Buscá cada línea en la hoja Registro de la planilla y confirmá fecha, atleta, ejercicio, serie,');
  stdout.writeln('kilos y reps. La columna "app" es lo que quedó cargado.');
  final rows = {for (final r in _registroRows(run)) r.line: r};
  final athletes = HistoryImport.sheetAthletes(run);
  final loaded = [
    for (final s in plan.sessions)
      for (final set in s.sets)
        if (s.stored[set.position] case final record?) (s, set, record),
  ]..shuffle(Random(seed));
  final picked = loaded.take(size).toList()..sort((a, b) => a.$2.line.compareTo(b.$2.line));
  var differs = 0;
  for (final (session, set, record) in picked) {
    final row = rows[set.line]!;
    final same = row.kg == record.kg && row.reps == record.reps;
    if (!same) differs++;
    stdout.writeln(
      '${same ? '✓' : '✗'} línea ${row.line} · ${aIsoFecha(row.session.date)} · '
      '${athletes[row.athlete] ?? row.athlete} · ${row.exercise} · serie ${row.set ?? '-'}\n'
      '      planilla: ${_kg(row.kg)} kg × ${row.reps ?? '-'}    '
      'app: ${record.exerciseName}, ${_kg(record.kg)} kg × ${record.reps ?? '-'} (${session.label})',
    );
  }
  stdout.writeln('${differs == 0 ? '✓' : '✗'} ${picked.length} filas, $differs con kilos o reps distintos.');
  return differs == 0;
}

List<SheetRecordRow> _registroRows(ImportRun run) => HistorySheets.read(
  records: run.sheets.read(HistorySheetNames.records, columns: HistorySheetNames.recordColumns),
).records;

String _kg(double? kg) => kg == null ? '-' : (kg == kg.roundToDouble() ? '${kg.toInt()}' : '$kg');
