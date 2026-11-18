import 'dart:convert';
import 'dart:io';

import 'package:maktub_backend/features/import/adjustments.dart';
import 'package:maktub_backend/features/import/history/history_import.dart';
import 'package:maktub_backend/features/import/history/history_import_store.dart';
import 'package:maktub_backend/features/import/history/history_plan.dart';
import 'package:maktub_backend/features/import/history/history_sheets.dart';
import 'package:maktub_backend/features/import/import_run.dart';
import 'package:maktub_backend/features/import/plans/historic_plans.dart';
import 'package:maktub_backend/features/import/plans/plan_import_plan.dart';
import 'package:maktub_backend/features/import/plans/plan_sheets.dart';
import 'package:maktub_backend/features/import/sheets.dart';
import 'package:maktub_backend/features/sesion/open_session/open_session_store.dart';
import 'package:maktub_backend/features/sesion/record_block_time/record_block_time_store.dart';
import 'package:maktub_backend/features/sesion/record_set/record_set_store.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';
import '../../support/assignments.dart';

const _club = 'club1';
final _audit = Auditoria.nueva('coach', ahora: DateTime.utc(2026, 9, 1));

// Invented rows: the real spreadsheet is personal data and never enters the repo.
const _planSheets = {
  'Planes': '''
id,nombre,activo,inicio,secuencia
plan_oct,Octubre,TRUE,2026-10-01,
plan_borrador,Borrador,FALSE,2026-10-01,
''',
  'PlanModelos': 'plan,id,nombre,archivado\n',
  'PlanDias': '''
plan,dia,primario,estiramiento,calentamiento
plan_oct,1,sq,est_sq,
plan_borrador,1,sq,,
''',
  'PlanEjercicios': '''
plan,dia,bloque,grupo,orden,ejercicio,variante,serie,reps,pct,rpe,temporizador
plan_oct,1,principal,,1,sq,descarga,1,8,25,,
plan_oct,1,principal,,1,sq,descarga,2,5,50,,
plan_oct,1,principal,,1,sq,descarga,3,3,80,,
plan_oct,1,principal,,1,sq,carga,1,8,25,,
plan_oct,1,principal,,1,sq,carga,2,5,55,,
plan_oct,1,principal,,1,sq,carga,3,3,85,,
plan_oct,1,final,1,1,row_x,descarga,1,12,,,
plan_oct,1,final,1,1,row_x,descarga,2,12,,,
plan_oct,1,final,1,1,row_x,carga,1,12,,,
plan_borrador,1,principal,,1,sq,descarga,1,5,70,,
''',
  'PlanWods': 'plan,dia,variante,wod\n',
};

const _registroHeader =
    'fecha,atleta,ejercicio,bloque,serie,peso_kg,reps,rm_vigente,pct,nota,plan,ciclo,semana,dia,grupo,orden,modelo';

const _registro =
    '''
$_registroHeader
2026-10-01,a1,sq,principal,1,20,8,70,,buena,plan_oct,1,1,1,,1,descarga
2026-10-01,a1,sq,principal,2,35,5,70,,buena,plan_oct,1,1,1,,1,descarga
2026-10-01,a1,sq,principal,3,55,3,72,,,plan_oct,1,1,1,,1,descarga
2026-10-01,a2,sq,principal,1,30,8,,,,plan_oct,1,1,1,,1,descarga
2026-10-01,a1,row_x,final,1,12,12,,,,plan_oct,1,1,1,1,1,descarga
2026-10-01,a1,est_sq,estiramiento,,,,,,,plan_oct,1,1,1,,,descarga
2026-10-08,a1,sq,principal,3,56,3,70,85,,plan_oct,1,2,1,,1,carga
2025-08-01,a1,sq,principal,4,55,2,,,8 - 5 - 3,historico,1,1,1,,,
2025-08-08,a2,sq,principal,1,50,5,,,,historico,2,2,1,,,
2026-10-01,a1,sq,principal,1,40,5,,,,plan_borrador,1,1,1,,1,descarga
2026-10-01,a9,sq,principal,1,40,8,,,,plan_oct,1,1,1,,1,descarga
2026-10-01,a1,nada,principal,1,40,8,,,,plan_oct,1,1,1,,1,descarga
2026-10-01,a1,row_x,principal,1,12,12,,,,plan_oct,1,1,1,,1,descarga
2026-10-01,a1,sq,principal,1,40,8,,,,plan_oct,2,1,1,,1,descarga
2026-10-15,a1,sq,principal,1,,8,,,,plan_oct,1,3,1,,1,carga
2026-09-20,a1,sq,principal,1,40,8,,,,plan_oct,1,1,1,,1,descarga
''';

const _tiempos = '''
fecha,plan,ciclo,semana,dia,bloque,atletas,modo,inicio,fin,segundos,interrumpido
2026-10-01,plan_oct,1,1,1,Bloque primario: Sentadilla,"Ariadna, Andrés",turnos,2026-10-01T18:00:00,2026-10-01T18:10:00,600,FALSE
2026-10-01,plan_oct,1,1,1,Estiramiento,Ariadna,,2026-10-01T17:50:00,2026-10-01T17:55:30,330,TRUE
2026-10-01,plan_oct,1,1,1,Calentamiento,Pedro,,2026-10-01T17:56:00,2026-10-01T17:58:00,120,FALSE
''';

/// The club in memory: what the E7 use cases read and write.
class _Db {
  final plans = <String, Plan>{};
  final assignments = <Assignment>[];
  final groups = <String, List<String>>{
    'g1': ['ari', 'andi'],
  };
  final sessions = <String, Session>{};
  final records = <SetRecord>[];
  final times = <String, BlockTime>{};
  final references = <Reference>[];
  final exercises = <String, Exercise>{};
  final sequences = <String, int>{};
  var timeWrites = 0;

  String snapshot() => jsonEncode([
    [for (final s in sessions.values) s.toJson()],
    [for (final r in records) r.toJson()],
    [for (final t in times.values) t.toJson()],
  ]);
}

class _Reads implements HistoryImportStore {
  _Reads(this.db);

  final _Db db;

  @override
  Future<Map<String, Plan>> plans(String clubId, Set<String> ids) async => {
    for (final p in db.plans.values)
      if (p.clubId == clubId && ids.contains(p.id)) p.id: p,
  };

  @override
  Future<List<Assignment>> assignments(String clubId, Set<String> planIds) async =>
      db.assignments.where((a) => a.clubId == clubId && planIds.contains(a.planId)).toList();

  @override
  Future<Map<String, List<String>>> groupMembers(String clubId, Set<String> ids) async => {
    for (final id in ids) id: ?db.groups[id],
  };

  @override
  Future<List<Session>> sessions(String clubId, Set<String> assignmentIds) async =>
      db.sessions.values.where((s) => s.clubId == clubId && assignmentIds.contains(s.assignmentId)).toList();

  @override
  Future<List<SetRecord>> records(String clubId, Set<String> sessionIds) async =>
      db.records.where((r) => r.clubId == clubId && sessionIds.contains(r.sessionId)).toList();

  @override
  Future<List<BlockTime>> blockTimes(String clubId, Set<String> sessionIds) async =>
      db.times.values.where((t) => t.clubId == clubId && sessionIds.contains(t.sessionId)).toList();

  @override
  Future<List<FixedWeight>> fixedWeights(String clubId) async => const [];
}

Session _copy(Session s, {List<String>? present, int? sequence, int? lastSessionChange}) => Session(
  id: s.id,
  clubId: s.clubId,
  assignmentId: s.assignmentId,
  planId: s.planId,
  cycle: s.cycle,
  week: s.week,
  day: s.day,
  date: s.date,
  presentAthleteIds: present ?? s.presentAthleteIds,
  sequence: sequence ?? s.sequence,
  lastSessionChange: lastSessionChange ?? s.lastSessionChange,
  auditoria: s.auditoria,
);

class _Sessions implements OpenSessionStore {
  _Sessions(this.db);

  final _Db db;

  @override
  Future<Assignment?> assignment(String clubId, String assignmentId) async => withGroupMembers(
    db.assignments.where((a) => a.clubId == clubId && a.id == assignmentId).firstOrNull,
    (g) => groupMemberIds(clubId, g),
  );

  @override
  Future<PublishedPlan?> publishedPlan(String clubId, String planId) async => db.plans[planId]?.published;

  Future<List<String>> groupMemberIds(String clubId, String groupId) async => db.groups[groupId] ?? const [];

  @override
  Future<String?> athleteIdOfUser(String clubId, String userId) async => null;

  bool _same(Session a, Session b) =>
      a.clubId == b.clubId &&
      a.assignmentId == b.assignmentId &&
      a.date == b.date &&
      a.week == b.week &&
      a.day == b.day;

  @override
  Future<Session?> existing(Session candidate) async =>
      db.sessions.values.where((s) => _same(s, candidate)).firstOrNull;

  @override
  Future<Session> markChanged(String clubId, String sessionId) async {
    final n = db.sequences[sessionId] = (db.sequences[sessionId] ?? 0) + 1;
    return db.sessions[sessionId] = _copy(db.sessions[sessionId]!, sequence: n, lastSessionChange: n);
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
  Future<Map<String, Exercise>> exercises(String clubId) async => db.exercises;

  @override
  Future<List<Reference>> references(String clubId, String athleteId, String exerciseId) async =>
      db.references.where((r) => r.athleteId == athleteId && r.exerciseId == exerciseId).toList();

  @override
  Future<List<WorkFactor>> workFactors(String clubId, String athleteId, String exerciseId) async => const [];

  @override
  Future<FixedWeight?> fixedWeight(String clubId, String athleteId, String exerciseId) async => null;

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
    final old = db.records[i];
    final json = record.toJson()
      ..['id'] = old.id
      ..['auditoria'] = old.auditoria.modificada(importAuthor, ahora: record.auditoria.modificadoEn).toJson();
    if (keepNote) json['nota'] = old.note;
    return db.records[i] = SetRecord.fromJson(json);
  }
}

class _Times implements RecordBlockTimeStore {
  _Times(this.db);

  final _Db db;

  @override
  Future<Session?> session(String clubId, String sessionId) async => db.sessions[sessionId];

  @override
  Future<String?> athleteIdOfUser(String clubId, String userId) async => null;

  @override
  Future<BlockTime> upsert(BlockTime time) async {
    db.timeWrites++;
    return db.times[time.id] = time;
  }
}

Exercise _exercise(
  String id,
  List<Metric> metrics, {
  LoadReference ref = const LoadReference.none(),
  List<String> categories = const [],
}) => Exercise(
  id: id,
  clubId: _club,
  name: id.toUpperCase(),
  categoryIds: categories,
  metrics: metrics,
  defaultMetric: metrics.first,
  loadReference: ref,
  auditoria: _audit,
);

Sheet _sheet(String name, String csv, List<String> columns) => Sheet.parse(name, csv.trimLeft(), columns: columns);

/// E8.4's own planning over the invented plan sheets plus the month plans of the `historico` rows, with October's
/// correction, as the history step gets it (what `PlanImport.plan` does).
PlanImportPlan _plans(Map<String, Exercise> exercises) {
  final sheets = PlanSheets.read(
    plans: _sheet('Planes', _planSheets['Planes']!, PlanSheetNames.planColumns),
    weekModels: _sheet('PlanModelos', _planSheets['PlanModelos']!, PlanSheetNames.weekModelColumns),
    days: _sheet('PlanDias', _planSheets['PlanDias']!, PlanSheetNames.dayColumns),
    sets: _sheet('PlanEjercicios', _planSheets['PlanEjercicios']!, PlanSheetNames.setColumns),
    wods: _sheet('PlanWods', _planSheets['PlanWods']!, PlanSheetNames.wodColumns),
  );
  final historic = historicPlans(
    HistorySheets.read(records: _sheet('Registro', _registro, HistorySheetNames.recordColumns)).records,
    categoriesOf: (id) => exercises[id]?.categoryIds ?? const [],
  );
  sheets.plans.addAll(historic.plans);
  return planPlanImport(
    sheets,
    PlanCatalog(
      exerciseIdFor: (id) => exercises.containsKey(id) ? id : null,
      timerIdFor: (_) => null,
      exercises: exercises,
      sheetExercises: const [],
    ),
    clubId: _club,
    existing: const {},
    now: DateTime.utc(2026, 9, 1),
    corrections: const [PctCorrection(planId: 'plan_oct', from: 85, to: 80)],
  )..historic = historic;
}

void main() {
  late Directory dir;
  late _Db db;
  late PlanImportPlan plans;
  var pending = <String>[];

  String planId(String sheetId) => importedId(_club, sheetId);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('history_import_test');
    File('${dir.path}/Registro.csv').writeAsStringSync(_registro.trimLeft());
    File('${dir.path}/Tiempos.csv').writeAsStringSync(_tiempos.trimLeft());
    pending = [];
    db = _Db();
    db.exercises.addAll({
      'sq': _exercise(
        'sq',
        const [Metric.loadPctRm, Metric.reps],
        ref: const LoadReference.own(),
        categories: const ['primario'],
      ),
      'row_x': _exercise('row_x', const [Metric.fixedLoad, Metric.reps], categories: const ['accesorio']),
      'est_sq': _exercise('est_sq', const [Metric.time], categories: const ['estiramiento']),
    });
    plans = _plans(db.exercises);
    // Both plans as E8.4 creates them; only plan_oct published (the other stays a draft).
    for (final p in plans.toCreate) {
      final plan = p.plan;
      db.plans[plan.id] = Plan(
        id: plan.id,
        clubId: _club,
        name: plan.name,
        weekModels: plan.weekModels,
        weekAssignment: plan.weekAssignment,
        published: p.sheetId != 'plan_borrador'
            ? PublishedPlan(
                weekModels: plan.weekModels,
                weekAssignment: plan.weekAssignment,
                publishedAt: DateTime.utc(2026, 9, 1),
                publishedBy: 'coach',
              )
            : null,
        auditoria: _audit,
      );
    }
    for (final (sheetId, start, end) in [
      ('plan_oct', DateTime.utc(2026, 10, 1), DateTime.utc(2026, 10, 31)),
      ('plan_borrador', DateTime.utc(2026, 10, 1), DateTime.utc(2026, 10, 31)),
      ('historico-2025-08', DateTime.utc(2025, 8, 1), DateTime.utc(2025, 8, 31)),
    ]) {
      db.assignments.add(
        Assignment(
          id: 'asig-$sheetId',
          clubId: _club,
          planId: planId(sheetId),
          groupId: 'g1',
          startDate: start,
          status: AssignmentStatus.ended,
          endDate: end,
          auditoria: _audit,
        ),
      );
    }
    db.references.add(
      Reference(
        id: 'rm-ari-sq',
        clubId: _club,
        athleteId: 'ari',
        exerciseId: 'sq',
        type: ReferenceType.rm,
        value: 70,
        date: DateTime.utc(2026, 9, 1),
        origin: ReferenceOrigin.importado,
        auditoria: _audit,
      ),
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  HistoryImport importer({DateTime? now}) => HistoryImport(
    sources: (run) async => HistorySources(
      exerciseIdFor: (id) => db.exercises.containsKey(id) ? id : null,
      athleteIdFor: (id) => const {'a1': 'ari', 'a2': 'andi'}[id],
      sheetAthletes: const {'a1': 'Ariadna', 'a2': 'Andres'},
      plans: plans,
      pending: pending,
    ),
    reads: _Reads(db),
    sessionWrites: _Sessions(db),
    setWrites: _Sets(db),
    timeWrites: _Times(db),
    now: () => now ?? DateTime.utc(2026, 11, 15),
  );
  ImportRun run({bool dryRun = false}) => ImportRun(
    club: importClubContext(_club, TipoClub.club),
    sheets: SheetDirectory(dir.path),
    adjustments: const ImportAdjustments(),
    dryRun: dryRun,
  );

  Session sessionOn(DateTime date) => db.sessions.values.singleWhere((s) => s.date == date);
  List<SetRecord> recordsOf(Session s, String athlete) =>
      db.records.where((r) => r.sessionId == s.id && r.athleteId == athlete).toList()
        ..sort((a, b) => '${a.blockIndex}${a.setIndex}'.compareTo('${b.blockIndex}${b.setIndex}'));

  test('each row becomes an E7 set of the session of its date, plan, cycle, week and day', () async {
    await importer().run(run());
    final s = sessionOn(DateTime.utc(2026, 10, 1));
    expect(s.assignmentId, 'asig-plan_oct', reason: 'an ended assignment still takes its history');
    expect(s.planId, planId('plan_oct'));
    expect((s.cycle, s.week, s.day), (1, 1, 1));
    expect(s.presentAthleteIds, unorderedEquals(['ari', 'andi']));
    expect(s.id, stableImportId(_club, 'sesion', ['2026-10-01|plan_oct|1|1|1']));

    final ari = recordsOf(s, 'ari');
    // Blocks: Estiramiento (0), Primario (1), Accesorios (2).
    expect(
      [for (final r in ari) (r.blockIndex, r.setIndex, r.kg, r.reps)],
      [(1, 0, 20.0, 8), (1, 1, 35.0, 5), (1, 2, 55.0, 3), (2, 0, 12.0, 12)],
    );
    final first = ari.first;
    expect(first.manualKg, isTrue, reason: 'the sheet kilos are typed kilos');
    expect(first.target.pct, 25);
    expect(first.referenceValue, 70, reason: 'the RM of E8.3 in force that day');
    expect(first.pctReal, closeTo(28.57, 0.01), reason: 'percents follow from the kilos and the RM');
    expect(first.note, 'buena', reason: 'the note goes on the first set, once');
    expect(ari[1].note, isNull);
    expect(first.id, stableImportId(_club, 'serie', ['2026-10-01|plan_oct|1|1|1', 'a1', 'principal', '', 1, 'sq', 1]));
    expect(first.exerciseName, 'SQ');
    expect(recordsOf(s, 'andi').single.referenceValue, isNull, reason: 'no RM for that athlete: kilos only');
  });

  test('a historico row loads into the plan of its month, in cycle 1 of it', () async {
    final report = await importer().run(run());
    final s = sessionOn(DateTime.utc(2025, 8, 1));
    expect(s.planId, planId('historico-2025-08'));
    expect(s.assignmentId, 'asig-historico-2025-08');
    expect((s.cycle, s.week, s.day), (1, 1, 1));
    final record = recordsOf(s, 'ari').single;
    expect((record.blockIndex, record.setIndex, record.kg, record.reps), (0, 0, 55.0, 2));
    expect(record.manualKg, isTrue);
    expect(record.note, '8 - 5 - 3');
    expect(record.target.pct, isNull, reason: 'the sheet never had a %');
    expect(sessionOn(DateTime.utc(2025, 8, 8)).cycle, 1, reason: 'the sheet says cycle 2: the plan was repeated');
    expect(report.notes, contains(allOf(contains('historico-2025-08'), contains('ciclo 2'))));
  });

  test('October sets carry the E8.4 correction in their target', () async {
    await importer().run(run());
    final record = recordsOf(sessionOn(DateTime.utc(2026, 10, 8)), 'ari').single;
    expect(record.target.pct, 80, reason: 'the sheet plan says 85');
    expect(record.kg, 56);
  });

  test('Tiempos rows go to the block times of the session, athletes by name and instants in UTC', () async {
    await importer().run(run());
    final s = sessionOn(DateTime.utc(2026, 10, 1));
    final times = db.times.values.toList()..sort((a, b) => a.start.compareTo(b.start));
    expect(times, hasLength(2));
    expect({for (final t in times) t.sessionId}, {s.id});
    final stretch = times.first, primary = times.last;
    expect((stretch.blockIndex, stretch.athleteMode, stretch.interrupted), (0, null, true));
    expect(stretch.athleteIds, ['ari']);
    expect(primary.blockIndex, 1);
    expect(primary.blockName, 'Bloque primario: Sentadilla');
    expect(primary.athleteMode, AthleteMode.turns);
    expect(primary.athleteIds, ['ari', 'andi'], reason: '"Andrés" is "Andres" in Atletas');
    expect(primary.start, DateTime.utc(2026, 10, 1, 16), reason: 'the sheet is on Europe/Berlin (summer time)');
    expect(primary.seconds, 600);
    expect(
      primary.id,
      stableImportId(_club, 'tiempo', [
        '2026-10-01|plan_oct|1|1|1',
        'Bloque primario: Sentadilla',
        '2026-10-01T16:00:00.000Z',
      ]),
    );
  });

  test('every row that is not loaded is reported with its reason', () async {
    final report = await importer().run(run());
    String problem(String text) => report.problems.singleWhere((p) => p.contains(text));
    expect(problem('"Borrador" (plan_borrador) está en borrador'), contains('líneas 11)'));
    expect(problem('a9'), contains('no está vinculado'));
    expect(problem('"nada"'), contains('catálogo'));
    expect(problem('posición del plan'), contains('líneas 14)'));
    expect(problem('ciclo 1 y la planilla dice 2'), contains('líneas 15)'));
    expect(problem('no se inventan'), contains('líneas 16)'));
    expect(problem('asignación que cubra'), contains('líneas 17)'));
    expect(problem('"Pedro"'), startsWith('Tiempos: 1 filas'));
    expect(report.problems, hasLength(8));
    expect(report.notes, contains(allOf(contains('sin series en el plan'), contains('líneas 7)'))));
    expect(report.notes, contains(allOf(contains('línea 4'), contains('RM 72 '))));
    expect(db.records, hasLength(8), reason: '5 sets on Oct 1, 1 on Oct 8 and 2 of the history plan');
  });

  test("an athlete's own assignment (E8.8) loads that athlete's rows and reports the others'", () async {
    final i = db.assignments.indexWhere((a) => a.id == 'asig-plan_oct');
    final group = db.assignments[i];
    db.assignments[i] = Assignment(
      id: group.id,
      clubId: _club,
      planId: group.planId,
      members: [AssignmentMember(athleteId: 'ari', from: group.startDate)],
      startDate: group.startDate,
      status: AssignmentStatus.ended,
      endDate: group.endDate,
      auditoria: _audit,
    );
    final report = await importer().run(run());
    final s = sessionOn(DateTime.utc(2026, 10, 1));
    expect(s.presentAthleteIds, ['ari']);
    expect(recordsOf(s, 'ari'), hasLength(4));
    expect(recordsOf(s, 'andi'), isEmpty);
    expect(report.problems, contains(contains('no está en la asignación')));
  });

  test('running twice writes nothing new: no duplicated sets, times or changes', () async {
    await importer().run(run());
    final before = db.snapshot();
    final timeWrites = db.timeWrites;
    final report = await importer(now: DateTime.utc(2026, 11, 16)).run(run());
    expect(db.snapshot(), before, reason: 'same ids, audits and change numbers');
    expect(db.timeWrites, timeWrites);
    expect(report.created, isEmpty);
    expect(report.updated, isEmpty);
    expect(report.unchanged, hasLength(4));
    expect(report.unchanged.first, contains('0 series escritas'));
  });

  test('a set changed in the app is put back as the sheet says, in the same document', () async {
    await importer().run(run());
    final i = db.records.indexWhere((r) => r.kg == 35);
    final id = db.records[i].id;
    db.records[i] = SetRecord.fromJson(db.records[i].toJson()..['kilos'] = 99);
    final report = await importer(now: DateTime.utc(2026, 11, 16)).run(run());
    expect(db.records, hasLength(8));
    expect(db.records.singleWhere((r) => r.id == id).kg, 35);
    expect(report.updated, [contains('1 series escritas')]);
  });

  test('a dry run writes nothing and says what it would do', () async {
    final report = await importer().run(run(dryRun: true));
    expect(db.sessions, isEmpty);
    expect(db.records, isEmpty);
    expect(db.times, isEmpty);
    expect(report.created, hasLength(4));
    expect(report.created, contains(contains('5 series, 2 tiempos')));
  });

  test('nothing is written while an earlier step has work left', () async {
    pending = ['planes'];
    final report = await importer().run(run());
    expect(db.sessions, isEmpty);
    expect(report.problems, contains(contains('"planes"')));
  });

  test('sheet wall-clock times follow Europe/Berlin, summer time included', () {
    expect(sheetLocalToUtc(DateTime(2026, 11, 5, 21, 31, 14)), DateTime.utc(2026, 11, 5, 20, 31, 14));
    expect(sheetLocalToUtc(DateTime(2026, 7, 1, 12)), DateTime.utc(2026, 7, 1, 10));
    expect(sheetLocalToUtc(DateTime(2026, 3, 29, 1, 30)), DateTime.utc(2026, 3, 29, 0, 30));
    expect(sheetLocalToUtc(DateTime(2026, 3, 29, 3, 30)), DateTime.utc(2026, 3, 29, 1, 30));
    expect(sheetLocalToUtc(DateTime(2026, 10, 25, 3, 30)), DateTime.utc(2026, 10, 25, 2, 30));
  });

  test('stable ids are UUID-shaped, differ by key and repeat for the same key', () {
    final a = stableImportId(_club, 'serie', ['x', 1]);
    expect(a, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(stableImportId(_club, 'serie', ['x', 1]), a);
    expect(stableImportId(_club, 'serie', ['x', 2]), isNot(a));
    expect(stableImportId('otro', 'serie', ['x', 1]), isNot(a));
  });
}
