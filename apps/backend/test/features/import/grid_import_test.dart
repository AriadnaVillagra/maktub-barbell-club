import 'dart:convert';

import 'package:maktub_backend/features/asignaciones/crear/crear_store.dart';
import 'package:maktub_backend/features/import/adjustments.dart';
import 'package:maktub_backend/features/import/grid/grid_import.dart';
import 'package:maktub_backend/features/import/grid/grid_import_store.dart';
import 'package:maktub_backend/features/import/grid/grid_plan.dart';
import 'package:maktub_backend/features/import/grid/grid_sheet.dart';
import 'package:maktub_backend/features/import/import_run.dart';
import 'package:maktub_backend/features/import/sheets.dart';
import 'package:maktub_backend/features/plan/crear/crear_store.dart';
import 'package:maktub_backend/features/plan/guardar/guardar_store.dart';
import 'package:maktub_backend/features/plan/publicar/publicar_store.dart';
import 'package:maktub_backend/features/sesion/live_broadcast.dart';
import 'package:maktub_backend/features/sesion/open_session/open_session_store.dart';
import 'package:maktub_backend/features/sesion/record_set/record_set.dart';
import 'package:maktub_backend/features/sesion/record_set/record_set_store.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

const _club = 'club1';
final _audit = Auditoria.nueva('coach', ahora: DateTime.utc(2026, 3, 1));

// An invented grid in the shape of the planning sheets (the real one is personal data and never enters the repo):
// four weeks of five columns from column 2, the days in column 1 and the KG RM table from column 22.
String _row(Map<int, Object> cells) {
  String quote(String s) => s.contains(RegExp('[,"\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
  return [for (var c = 0; c < 25; c++) quote('${cells[c] ?? ''}')].join(',');
}

/// The same cell in every week (column offset [offset] within the week).
Map<int, Object> _weeks(int offset, Object Function(int week) cell) => {
  for (var w = 1; w <= 4; w++) 2 + 5 * (w - 1) + offset: cell(w),
};

final _grid = [
  _row({..._weeks(0, (w) => 'SEMANA $w'), 22: 'KG RM', 23: 'ANA', 24: 'BETO'}),
  _row({1: 'DIA 1', ..._weeks(0, (_) => 'ENTRADA EN CALOR'), 22: 'BACK SQUAT', 23: 100, 24: 80}),
  _row({..._weeks(0, (_) => '3x10'), ..._weeks(1, (_) => 'abdominales\nsaltos'), 22: 'BENCH', 23: 50, 24: 40}),
  _row(_weeks(0, (_) => '3x12')),
  _row(_weeks(0, (_) => 'BLOQUE 1')),
  _row({..._weeks(0, (_) => 'Movilidad de cadera'), ..._weeks(3, (_) => 'Pesos usados ese día')}),
  _row({
    ..._weeks(0, (_) => '4X5'),
    ..._weeks(1, (w) => ['0.7', '0.75', '0.8', '0.6'][w - 1]),
    ..._weeks(2, (_) => 'back squat'),
  }),
  _row({..._weeks(0, (_) => '3x8'), ..._weeks(1, (_) => 'con barra'), ..._weeks(2, (_) => 'rumanos')}),
  _row(_weeks(0, (_) => 'descanso 2 min')),
  _row(_weeks(0, (_) => 'BLOQUE 2')),
  _row({
    ..._weeks(0, (_) => '3x10'),
    ..._weeks(1, (w) => w == 1 ? 'mancuerna 12kg' : 'mancuerna'),
    ..._weeks(2, (_) => 'curl'),
  }),
  _row({..._weeks(0, (_) => '3x10'), ..._weeks(2, (_) => 'molinete')}),
  _row(_weeks(0, (_) => 'WOD')),
  _row({1: 'no hicimos esto'}),
  _row({1: 'DIA 2', ..._weeks(0, (w) => w == 2 ? 'SEMANA 2 (beto no vino)' : 'SEMANA $w')}),
  _row(_weeks(0, (_) => 'ENTRADA EN CALOR')),
  _row({..._weeks(0, (_) => '2x10'), ..._weeks(1, (_) => 'abdominales')}),
  _row(_weeks(0, (_) => 'BLOQUE 1')),
  _row({..._weeks(0, (_) => '5/2x5/3'), ..._weeks(1, (_) => 'barra de 20'), ..._weeks(2, (_) => 'bench press')}),
  _row({7: '}'}),
  _row({..._weeks(0, (_) => 'WOD'), 18: 'SKILL\nsaltos'}),
].join('\n');

final _adjustments = {
  'planningGrid': {
    'sheet': 'GRILLA',
    'plan': {'id': 'plan-grilla', 'name': 'Abril'},
    'group': 'Ana y Beto',
    'months': ['2026-04', '2026-05'],
    'absent': [
      {'month': '2026-04', 'week': 2, 'day': 2, 'athlete': 'Beto'},
    ],
    'exerciseNames': {'Back Squat': 'sq', 'rumanos': 'rdl', 'bench press': 'bp', 'bench': 'bp'},
  },
};

Exercise _exercise(
  String id,
  String name,
  List<String> categories,
  List<Metric> metrics, {
  LoadReference ref = const LoadReference.none(),
}) => Exercise(
  id: id,
  clubId: clubPlataforma,
  name: name,
  categoryIds: categories,
  metrics: metrics,
  defaultMetric: metrics.first,
  loadReference: ref,
  auditoria: _audit,
);

final _exercises = {
  for (final e in [
    _exercise('sq', 'Sentadilla', ['primario'], [Metric.loadPctRm, Metric.reps], ref: const LoadReference.own()),
    _exercise('rdl', 'Peso muerto rumano', ['secundario'], [Metric.loadPctRm, Metric.reps], ref: const LoadReference.otherExercise('sq')),
    _exercise('bp', 'Bench press', ['primario'], [Metric.loadPctRm, Metric.reps], ref: const LoadReference.own()),
    _exercise('curl', 'Curl', ['accesorio'], [Metric.fixedLoad, Metric.reps]),
    _exercise('abs', 'Abdominales', ['calentamiento'], [Metric.reps]),
    _exercise('saltos', 'Saltos', ['calentamiento'], [Metric.reps]),
  ])
    e.id: e,
};

Reference _rm(String athlete, String exercise, double value) => Reference(
  id: 'rm-$athlete-$exercise',
  clubId: _club,
  athleteId: athlete,
  exerciseId: exercise,
  type: ReferenceType.rm,
  value: value,
  date: DateTime.utc(2026, 3, 1),
  origin: ReferenceOrigin.testeado,
  auditoria: _audit,
);

/// The club in memory, seen through the grid step's reads and the use cases' stores.
class _Db {
  final plans = <String, Plan>{};
  final assignments = <Assignment>[];
  final groups = [
    AthleteGroup(id: 'g1', clubId: _club, name: 'Ana y Beto', memberIds: const ['ana', 'beto'], auditoria: _audit),
  ];
  final athletes = {
    for (final (id, name) in [('ana', 'Ana'), ('beto', 'Beto')])
      id: Atleta(id: id, clubId: _club, usuarioId: 'u-$id', nombreVisible: name, auditoria: _audit),
  };
  final sessions = <String, Session>{};
  final records = <SetRecord>[];
  final references = [_rm('ana', 'sq', 100), _rm('beto', 'sq', 80), _rm('ana', 'bp', 50), _rm('beto', 'bp', 45)];
  final fixed = [
    FixedWeight(id: 'f1', clubId: _club, athleteId: 'ana', exerciseId: 'rdl', kg: 20, auditoria: _audit),
  ];
  final sequences = <String, int>{};

  String snapshot() => jsonEncode([
    [for (final p in plans.values) p.toJson()],
    [for (final a in assignments) a.toJson()],
    [for (final s in sessions.values) s.toJson()],
    [for (final r in records) r.toJson()],
  ]);
}

class _Reads implements GridImportStore {
  _Reads(this.db);

  final _Db db;

  @override
  Future<Plan?> plan(String clubId, String id) async => db.plans[id];

  @override
  Future<Assignment?> assignment(String clubId, String id) async => db.assignments.where((a) => a.id == id).firstOrNull;

  @override
  Future<List<AthleteGroup>> groups(String clubId) async => db.groups;

  @override
  Future<Map<String, Atleta>> athletes(String clubId, Set<String> ids) async => {
    for (final id in ids) id: ?db.athletes[id],
  };

  @override
  Future<Map<String, Exercise>> exercises(String clubId) async => _exercises;

  @override
  Future<List<Session>> sessions(String clubId, String assignmentId) async =>
      db.sessions.values.where((s) => s.assignmentId == assignmentId).toList();

  @override
  Future<List<SetRecord>> records(String clubId, Set<String> sessionIds) async =>
      db.records.where((r) => sessionIds.contains(r.sessionId)).toList();

  @override
  Future<List<Reference>> references(String clubId, Set<String> athleteIds) async =>
      db.references.where((r) => athleteIds.contains(r.athleteId)).toList();

  @override
  Future<List<WorkFactor>> workFactors(String clubId, Set<String> athleteIds) async => const [];

  @override
  Future<List<FixedWeight>> fixedWeights(String clubId, Set<String> athleteIds) async =>
      db.fixed.where((w) => athleteIds.contains(w.athleteId)).toList();

  @override
  Future<Equipo?> equipment(String clubId) async => null;
}

Plan _withPublished(Plan p, PublishedPlan? published) => Plan.fromJson({
  ...p.toJson()..remove('publicado'),
  if (published != null) 'publicado': published.toJson(),
});

class _Plans implements CreatePlanStore, SavePlanStore, PublishPlanStore {
  _Plans(this.db);

  final _Db db;

  @override
  Future<void> insert(Plan plan) async {
    if (db.plans.containsKey(plan.id)) throw StateError('duplicate _id ${plan.id}');
    db.plans[plan.id] = plan;
  }

  @override
  Future<Plan?> plan(String clubId, String planId) async => db.plans[planId];

  @override
  Future<Map<String, Exercise>> exercises(String clubId) async => _exercises;

  @override
  Future<bool> replace(Plan plan) async {
    final stored = db.plans[plan.id];
    if (stored == null) return false;
    db.plans[plan.id] = _withPublished(plan, stored.published);
    return true;
  }

  @override
  Future<bool> publish(String clubId, String planId, PublishedPlan copy, {required DateTime? savedAt}) async {
    final stored = db.plans[planId];
    if (stored == null) return false;
    db.plans[planId] = _withPublished(stored, copy);
    return true;
  }
}

class _Assignments implements CreateAssignmentStore {
  _Assignments(this.db);

  final _Db db;

  @override
  Future<Plan?> plan(String clubId, String planId) async => db.plans[planId];

  @override
  Future<List<String>?> groupMemberIds(String clubId, String groupId) async =>
      db.groups.where((g) => g.id == groupId).firstOrNull?.memberIds;

  @override
  Future<bool> athletesExist(String clubId, Set<String> athleteIds) async =>
      athleteIds.every(db.athletes.containsKey);

  @override
  Future<void> insert(Assignment assignment) async {
    if (db.assignments.any((a) => a.id == assignment.id)) throw StateError('duplicate _id');
    db.assignments.add(assignment);
  }
}

class _Sessions implements OpenSessionStore {
  _Sessions(this.db);

  final _Db db;

  @override
  Future<Assignment?> assignment(String clubId, String assignmentId) async =>
      db.assignments.where((a) => a.id == assignmentId).firstOrNull;

  @override
  Future<PublishedPlan?> publishedPlan(String clubId, String planId) async => db.plans[planId]?.published;

  Future<List<String>> groupMemberIds(String clubId, String groupId) async =>
      db.groups.firstWhere((g) => g.id == groupId).memberIds;

  @override
  Future<String?> athleteIdOfUser(String clubId, String userId) async => null;

  bool _same(Session a, Session b) =>
      a.assignmentId == b.assignmentId && a.date == b.date && a.week == b.week && a.day == b.day;

  @override
  Future<Session?> existing(Session candidate) async =>
      db.sessions.values.where((s) => _same(s, candidate)).firstOrNull;

  Session _copy(Session s, {List<String>? present, int? sequence}) => Session.fromJson({
    ...s.toJson(),
    'presentes': ?present,
    if (sequence != null) ...{'secuencia': sequence, 'secuenciaSesion': sequence},
  });

  @override
  Future<Session> markChanged(String clubId, String sessionId) async {
    final n = db.sequences[sessionId] = (db.sequences[sessionId] ?? 0) + 1;
    return db.sessions[sessionId] = _copy(db.sessions[sessionId]!, sequence: n);
  }

  @override
  Future<Session> openOrResume(Session candidate) async {
    final stored = await existing(candidate);
    if (stored == null) return db.sessions[candidate.id] = candidate;
    return db.sessions[stored.id] = _copy(
      stored,
      present: {...stored.presentAthleteIds, ...candidate.presentAthleteIds}.toList(),
    );
  }

  @override
  Future<List<SetRecord>> records(String clubId, String sessionId) async =>
      db.records.where((r) => r.sessionId == sessionId).toList();
}

class _Sets implements RecordSetStore {
  _Sets(this.db);

  final _Db db;

  @override
  Future<Session?> session(String clubId, String sessionId) async => db.sessions[sessionId];

  @override
  Future<PublishedPlan?> publishedPlan(String clubId, String planId) async => db.plans[planId]?.published;

  @override
  Future<String?> athleteIdOfUser(String clubId, String userId) async => null;

  @override
  Future<Map<String, Exercise>> exercises(String clubId) async => _exercises;

  @override
  Future<List<Reference>> references(String clubId, String athleteId, String exerciseId) async =>
      db.references.where((r) => r.athleteId == athleteId && r.exerciseId == exerciseId).toList();

  @override
  Future<List<WorkFactor>> workFactors(String clubId, String athleteId, String exerciseId) async => const [];

  @override
  Future<FixedWeight?> fixedWeight(String clubId, String athleteId, String exerciseId) async =>
      db.fixed.where((w) => w.athleteId == athleteId && w.exerciseId == exerciseId).firstOrNull;

  @override
  Future<Equipo?> equipment(String clubId) async => null;

  bool _same(SetRecord a, SetRecord b) =>
      a.sessionId == b.sessionId &&
      a.athleteId == b.athleteId &&
      a.blockIndex == b.blockIndex &&
      a.prescriptionIndex == b.prescriptionIndex &&
      a.setIndex == b.setIndex;

  @override
  Future<SetRecord?> stored(SetRecord record) async => db.records.where((r) => _same(r, record)).firstOrNull;

  @override
  Future<int> nextSequence(String clubId, String sessionId) async =>
      db.sequences[sessionId] = (db.sequences[sessionId] ?? 0) + 1;

  @override
  Future<SetRecord> upsert(SetRecord record, {bool keepNote = false}) async {
    final i = db.records.indexWhere((r) => _same(r, record));
    if (i < 0) {
      db.records.add(record);
      return record;
    }
    final json = record.toJson()..['id'] = db.records[i].id;
    if (keepNote) json['nota'] = db.records[i].note;
    return db.records[i] = SetRecord.fromJson(json);
  }
}

GridImport _step(_Db db, {List<String> pending = const []}) => GridImport(
  sources: (_) async => GridSources(exerciseIdFor: (id) => null, pending: pending),
  gridCsv: (sheet) => sheet == 'GRILLA' ? _grid : throw StateError('grilla $sheet'),
  reads: _Reads(db),
  planCreates: _Plans(db),
  planSaves: _Plans(db),
  planPublishes: _Plans(db),
  assignmentWrites: _Assignments(db),
  sessionWrites: _Sessions(db),
  setWrites: _Sets(db),
  now: () => DateTime.utc(2026, 11, 15, 12),
);

ImportRun _run({bool dryRun = false}) => ImportRun(
  club: importClubContext(_club, TipoClub.club),
  sheets: SheetDirectory('no-se-lee'),
  adjustments: ImportAdjustments.fromJson(_adjustments),
  dryRun: dryRun,
);

String get _planId => importedId(_club, 'plan-grilla');

void main() {
  group('the grid cells', () {
    test('sets: uniform, one by one, mixed, and what follows them', () {
      expect(parseGridSets('4X6')?.reps, [6, 6, 6, 6]);
      expect(parseGridSets('10/10/8/6/4/2')?.reps, [10, 10, 8, 6, 4, 2]);
      expect(parseGridSets('7/2x5/3x3')?.reps, [7, 5, 5, 3, 3, 3]);
      expect(parseGridSets('7/2x5/3/2x2')?.reps, [7, 5, 5, 3, 2, 2]);
      final sided = parseGridSets('3x10 c/lado')!;
      expect(sided.reps, [10, 10, 10]);
      expect(sided.rest, 'c/lado');
      expect(parseGridSets('4X10 pasos')?.rest, 'pasos');
      expect(parseGridSets(''), isNull);
      expect(parseGridSets('máximo'), isNull);
    });

    test('load: a %, kilos the cell writes, the bar, and anything else as a note', () {
      expect(parseGridLoad('0.65').pct, 65);
      expect(parseGridLoad('0.65').note, isNull);
      expect(parseGridLoad('72').pct, 72);
      final kg = parseGridLoad('mancuerna 12kg');
      expect([kg.kg, kg.pct, kg.note], [12, null, 'mancuerna 12kg']);
      final bar = parseGridLoad('barra de 20');
      expect([bar.barKg, bar.kg, bar.note], [20, null, 'barra de 20']);
      final either = parseGridLoad('barra de 15/20');
      expect([either.barKg, either.kg, either.note], [null, null, 'barra de 15/20']);
      expect(parseGridLoad('con barra').kg, isNull);
    });
  });

  group('reading the grid', () {
    final grid = PlanningGrid.parse(_grid);

    test('weeks, days and blocks in order', () {
      expect(grid.weeks, [1, 2, 3, 4]);
      expect(grid.days.keys, [1, 2]);
      expect([for (final b in grid.days[1]![1]!) b.name], ['Entrada en calor', 'Bloque 1', 'Bloque 2', 'WOD']);
      expect([for (final b in grid.days[2]![4]!) b.name], ['Entrada en calor', 'Bloque 1', 'WOD']);
    });

    test('the warm-up pairs the exercises of one cell with its sets rows', () {
      final warmUp = grid.days[1]![1]!.first;
      expect([for (final e in warmUp.entries) (e.exercise, e.sets)], [('abdominales', '3x10'), ('saltos', '3x12')]);
    });

    test('block rows: exercise, sets and load; other lines are notes', () {
      final block = grid.days[1]![2]![1];
      expect([for (final e in block.entries) (e.exercise, e.sets, e.load)], [
        ('back squat', '4X5', '0.75'),
        ('rumanos', '3x8', 'con barra'),
      ]);
      expect(block.notes, ['Movilidad de cadera', 'descanso 2 min']);
      expect(grid.days[2]![4]!.last.notes, ['SKILL', 'saltos']);
    });

    test('the KG RM table, the skipped rows, the remarks and the junk', () {
      expect([for (final r in grid.rms) (r.exercise, r.athlete, r.kg)], [
        ('BACK SQUAT', 'ANA', 100),
        ('BACK SQUAT', 'BETO', 80),
        ('BENCH', 'ANA', 50),
        ('BENCH', 'BETO', 40),
      ]);
      expect(grid.skippedRows, [14]);
      expect(grid.dayRemarks, {'2|2': 'beto no vino'});
      expect(grid.ignored.single, contains('"}"'));
    });
  });

  group('planning', () {
    GridImportPlan plan([GridState? state]) {
      final db = _Db();
      return planGridImport(
        PlanningGrid.parse(_grid),
        GridAdjustments.fromRaw(_adjustments)!,
        GridCatalog(exerciseIdFor: (_) => null, exercises: _exercises),
        state ??
            GridState(
              groups: db.groups,
              athletes: db.athletes,
              references: db.references,
              fixedWeights: db.fixed,
            ),
        clubId: _club,
        now: DateTime.utc(2026, 11, 15),
      );
    }

    test('a history plan with one week model per grid week, published', () {
      final p = plan();
      expect(p.createPlan, isTrue);
      expect(p.publishable, isTrue);
      expect(p.plan.type, PlanType.history);
      expect(p.plan.name, 'Abril');
      expect(p.plan.weekAssignment, ['s1', 's2', 's3', 's4']);
      expect(p.plan.weekModels.map((m) => m.days.length), [2, 2, 2, 2]);
    });

    test('blocks keep the grid, split by category when their exercises share none', () {
      final day1 = p1Day(plan(), week: 1, day: 1);
      expect([for (final b in day1) (b.name, b.categoryId)], [
        ('Entrada en calor', 'calentamiento'),
        ('Bloque 1 · Primario', 'primario'),
        ('Bloque 1 · Secundario', 'secundario'),
        ('Bloque 2', 'accesorio'),
      ]);
      expect(day1[1].note, 'Movilidad de cadera · descanso 2 min');
      final squat = day1[1].prescriptions.single;
      expect(squat.sets.map((s) => (s.reps, s.pct)), List.filled(4, (5, 70.0)));
      expect(day1[2].prescriptions.single.note, 'con barra');
      expect(day1[3].prescriptions.single.sets.first.kg, 12);
      expect(p1Day(plan(), week: 2, day: 1)[3].prescriptions.single.sets.first.kg, isNull);
    });

    test('the bar and the WOD, with the exercises it names', () {
      final day2 = p1Day(plan(), week: 4, day: 2);
      final bench = day2[1].prescriptions.single;
      expect(bench.barKg, 20);
      expect(bench.note, 'barra de 20');
      expect(bench.sets.map((s) => s.reps), [5, 5, 5, 3]);
      expect(day2.last.categoryId, wodCategoryId);
      expect(day2.last.note, 'SKILL · saltos');
      expect(day2.last.prescriptions.single.exerciseId, 'saltos');
      expect(p1Day(plan(), week: 1, day: 2).map((b) => b.name), ['Entrada en calor', 'Bloque 1']);
    });

    test('a name the catalog does not have is reported, never invented', () {
      expect(plan().report.problems, contains(allOf(contains('"molinete"'), contains('no está en el catálogo'))));
    });

    test('an ended assignment from the first to the last day of the months', () {
      final p = plan();
      expect(p.assignmentBody, {'planId': _planId, 'grupoId': 'g1', 'fechaInicio': '2026-04-01', 'fechaFin': '2026-05-31'});
    });

    test('sessions on day 7·(s−1)+d of each month, without who missed the day', () {
      final p = plan();
      expect(p.sessions.map((s) => s.openBody['fecha']), [
        '2026-04-01', '2026-04-02', '2026-04-08', '2026-04-09', '2026-04-15', '2026-04-16', '2026-04-22', //
        '2026-04-23', '2026-05-01', '2026-05-02', '2026-05-08', '2026-05-09', '2026-05-15', '2026-05-16', //
        '2026-05-22', '2026-05-23',
      ]);
      final absent = p.sessions.firstWhere((s) => s.openBody['fecha'] == '2026-04-09');
      expect(absent.openBody, {'asignacionId': p.assignmentId, 'fecha': '2026-04-09', 'semana': 2, 'dia': 2, 'presentes': ['ana']});
      expect(p.sessions.firstWhere((s) => s.openBody['fecha'] == '2026-05-09').openBody['presentes'], ['ana', 'beto']);
    });

    test('estimated sets with the kilos the app proposes, or without kilos when there are none', () {
      final first = plan().sessions.first;
      Iterable<(Object?, double?)> of(String athlete) =>
          first.sets.where((s) => s.body['atletaId'] == athlete).map((s) => (s.body['prescripcion'], s.kg));
      // Ana: warm-up (6, no load), squat at 70 % of 100, RDL at her fixed 20, curl at the grid's 12.
      expect(first.sets.where((s) => s.body['atletaId'] == 'ana'), hasLength(16));
      expect(first.sets.every((s) => s.body['estimada'] == true && s.body['hecha'] == true), isTrue);
      expect(first.sets.every((s) => !s.body.containsKey('kilos')), isTrue);
      expect(
        first.sets.where((s) => s.body['atletaId'] == 'ana' && s.body['bloque'] == 1).map((s) => s.kg),
        List.filled(4, 70.0),
      );
      expect(
        first.sets.where((s) => s.body['atletaId'] == 'ana' && s.body['bloque'] == 2).map((s) => s.kg),
        List.filled(3, 20.0),
      );
      // Beto: the RDL has no % and he has no fixed weight, so it goes done without kilos (never invented).
      final betoRdl = first.sets.where((s) => s.body['atletaId'] == 'beto' && s.body['bloque'] == 2).toList();
      expect(betoRdl.map((s) => s.kg), [null, null, null]);
      expect(betoRdl.every((s) => s.body['estimada'] == true && s.body['hecha'] == true), isTrue);
      expect(of('beto').where((s) => s.$2 == null), hasLength(9));
      final notes = plan().report.notes;
      expect(notes, contains(allOf(contains('sin kilos'), contains('Peso muerto rumano ("con barra")'), contains('(Beto)'))));
      expect(notes, contains(allOf(contains('sin kilos'), contains('Curl ("mancuerna")'), contains('Ana, Beto'))));
      expect(notes, contains(allOf(contains('kilaje fijo'), contains('Peso muerto rumano'), contains('(Ana)'))));
      expect(plan().report.problems, isNot(contains(contains('no se cargan'))));
    });

    test('a grid RM that differs from the app is reported', () {
      final notes = plan().report.notes;
      expect(notes, contains(allOf(contains('BETO BENCH 40'), contains('la app usa 45'))));
      expect(notes, contains(contains('3 de 4 coinciden')));
    });

    test('a set corrected in the app (no longer estimated) is never written again', () {
      final db = _Db();
      final assignmentId = gridAssignmentId(_club, GridAdjustments.fromRaw(_adjustments)!);
      final session = Session(
        id: 'ses',
        clubId: _club,
        assignmentId: assignmentId,
        planId: _planId,
        cycle: 1,
        week: 1,
        day: 1,
        date: DateTime.utc(2026, 4, 1),
        presentAthleteIds: const ['ana', 'beto'],
        auditoria: _audit,
      );
      SetRecord record(int set, {required bool estimated}) => SetRecord(
        id: 'r$set',
        clubId: _club,
        sessionId: 'ses',
        athleteId: 'ana',
        exerciseId: 'sq',
        exerciseName: 'Sentadilla',
        blockIndex: 1,
        prescriptionIndex: 0,
        setIndex: set,
        kg: 99,
        manualKg: !estimated,
        estimated: estimated,
        writtenBy: 'coach',
        auditoria: _audit,
      );
      final p = plan(
        GridState(
          groups: db.groups,
          athletes: db.athletes,
          references: db.references,
          fixedWeights: db.fixed,
          sessions: [session],
          records: [record(0, estimated: false), record(1, estimated: true)],
        ),
      );
      final first = p.sessions.first;
      expect(first.existing?.id, 'ses');
      expect(first.kept, 1);
      final squat = first.sets.where((s) => s.body['atletaId'] == 'ana' && s.body['bloque'] == 1).toList();
      expect(squat.map((s) => s.body['serie']), [1, 2, 3]);
      expect(squat.first.stored?.id, 'r1');
      expect(p.report.notes, contains(contains('1 series ya corregidas en la app')));
    });
  });

  group('the step', () {
    test('loads the plan, the assignment and the estimated sessions through the use cases', () async {
      final db = _Db();
      final report = await _step(db).run(_run());

      final plan = db.plans[_planId]!;
      expect(plan.type, PlanType.history);
      expect(plan.published, isNotNull);
      final assignment = db.assignments.single;
      expect([assignment.status, assignment.startDate, assignment.endDate], [
        AssignmentStatus.ended,
        DateTime.utc(2026, 4, 1),
        DateTime.utc(2026, 5, 31),
      ]);
      expect(db.sessions, hasLength(16));
      expect(db.records, isNotEmpty);
      expect(db.records.every((r) => r.estimated && r.done && !r.manualKg), isTrue);
      final squat = db.records.where((r) => r.athleteId == 'ana' && r.exerciseId == 'sq').toList();
      expect(squat.first.kg, 70);
      expect(squat.first.pctPlan, 70);
      expect(report.notes, isNot(contains(contains('se esperaban'))));
      expect(db.sessions.values.firstWhere((s) => s.date == DateTime.utc(2026, 4, 9)).presentAthleteIds, ['ana']);
    });

    test('a second run changes nothing', () async {
      final db = _Db();
      await _step(db).run(_run());
      final before = db.snapshot();

      final report = await _step(db).run(_run());

      expect(db.snapshot(), before);
      expect(report.created, isEmpty);
      expect(report.updated, isEmpty);
      expect(report.notes, contains(contains('0 escritas')));
    });

    test('a set corrected in the app survives a re-run', () async {
      final db = _Db();
      await _step(db).run(_run());
      final i = db.records.indexWhere((r) => r.athleteId == 'ana' && r.exerciseId == 'sq');
      db.records[i] = SetRecord.fromJson({
        ...db.records[i].toJson()..remove('estimada'),
        'kilos': 99,
        'kilosManual': true,
      });
      final corrected = jsonEncode(db.records[i].toJson());

      await _step(db).run(_run());

      expect(jsonEncode(db.records[i].toJson()), corrected);
    });

    test('a set without kilos is stored estimated; typing its kilos in the app makes it recorded, and a re-run keeps it', () async {
      final db = _Db();
      await _step(db).run(_run());
      final empty = db.records.firstWhere((r) => r.athleteId == 'beto' && r.exerciseId == 'rdl');
      expect([empty.kg, empty.estimated, empty.done, empty.reps], [null, true, true, 8]);
      final session = db.sessions[empty.sessionId]!;

      final typed = await RecordSet(_Sets(db), MemoryLiveBroadcast())(
        importClubContext(_club, TipoClub.club),
        session.id,
        {
          'atletaId': 'beto',
          'bloque': empty.blockIndex,
          'prescripcion': empty.prescriptionIndex,
          'serie': empty.setIndex,
          'hecha': true,
          'kilosManual': true,
          'kilos': 40,
          'estimada': true,
        },
      );
      expect([typed.kg, typed.manualKg, typed.estimated], [40, true, false]);
      final after = jsonEncode(typed.toJson());

      final report = await _step(db).run(_run());

      final again = db.records.firstWhere((r) => r.id == typed.id);
      expect(jsonEncode(again.toJson()), after);
      expect(report.notes, contains(contains('1 series ya corregidas en la app')));
    });

    test('a dry run writes nothing', () async {
      final db = _Db();
      final report = await _step(db).run(_run(dryRun: true));

      expect(db.snapshot(), _Db().snapshot());
      expect(report.created, hasLength(2 + 16));
    });

    test('while an earlier step is pending nothing about the sessions is written', () async {
      final db = _Db();
      final report = await _step(db, pending: ['catalogo']).run(_run());

      expect(db.plans, isEmpty);
      expect(db.sessions, isEmpty);
      expect(db.assignments, isEmpty);
      expect(report.problems, contains(contains('"catalogo"')));
    });
  });
}

List<PlanBlock> p1Day(GridImportPlan p, {required int week, required int day}) =>
    p.plan.weekModels[week - 1].days[day - 1].blocks;
