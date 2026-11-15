import 'dart:convert';
import 'dart:io';

import 'package:maktub_backend/features/catalogo/create_timer/create_timer_store.dart';
import 'package:maktub_backend/features/catalogo/write_exercise/write_exercise_store.dart';
import 'package:maktub_backend/features/import/adjustments.dart';
import 'package:maktub_backend/features/import/catalog/catalog_import.dart';
import 'package:maktub_backend/features/import/catalog/catalog_import_store.dart';
import 'package:maktub_backend/features/import/import_run.dart';
import 'package:maktub_backend/features/import/plans/plan_import.dart';
import 'package:maktub_backend/features/import/plans/plan_import_store.dart';
import 'package:maktub_backend/features/import/sheets.dart';
import 'package:maktub_backend/features/plan/crear/crear_store.dart';
import 'package:maktub_backend/features/plan/guardar/guardar_store.dart';
import 'package:maktub_backend/features/plan/publicar/publicar_store.dart';
import 'package:maktub_backend/features/wods/crear/crear_store.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

const _club = 'club1';
final _audit = Auditoria.nueva('sistema:semilla', ahora: DateTime.utc(2026, 11, 7));

/// The club's catalog and plans in memory.
class _Db {
  final exercises = <Exercise>[];
  final categories = <Category>[];
  final timers = <Temporizador>[];
  final wods = <Wod>[];
  final plans = <String, Plan>{};
  var planWrites = 0;

  Map<String, Exercise> visible(String clubId) => {
    for (final e in exercises)
      if (isVisibleTo(e, clubId)) e.id: e,
  };
}

class _CatalogStores implements CatalogImportStore, WriteExerciseStore, CreateTimerStore, CreateWodStore {
  _CatalogStores(this.db);

  final _Db db;

  @override
  Future<CatalogView> view(Set<String> clubIds) async => CatalogView.of(
    exercises: db.exercises.where((e) => clubIds.contains(e.clubId)),
    categories: db.categories.where((c) => clubIds.contains(c.clubId)),
  );

  @override
  Future<List<Temporizador>> timers(Set<String> clubIds) async =>
      db.timers.where((t) => clubIds.contains(t.clubId)).toList();

  @override
  Future<List<Wod>> wods(String clubId) async => db.wods.where((w) => w.clubId == clubId).toList();

  @override
  Future<void> insert(Object item) async {
    switch (item) {
      case final Exercise e:
        db.exercises.add(e);
      case final Temporizador t:
        db.timers.add(t);
      case final Wod w:
        db.wods.add(w);
    }
  }

  @override
  Future<void> replace(Exercise exercise) async {
    final i = db.exercises.indexWhere((e) => e.id == exercise.id && e.clubId == exercise.clubId);
    db.exercises[i] = exercise;
  }

  @override
  Future<void> delete(String clubId, String id) => throw UnimplementedError();
}

class _PlanReads implements PlanImportStore {
  _PlanReads(this.db);

  final _Db db;

  @override
  Future<Map<String, Plan>> plans(String clubId, Set<String> ids) async => {
    for (final p in db.plans.values)
      if (p.clubId == clubId && ids.contains(p.id)) p.id: p,
  };

  @override
  Future<List<Exercise>> exercises(String clubId) async => db.visible(clubId).values.toList();
}

Plan _with(Plan p, {List<WeekModel>? weekModels, PublishedPlan? published, Auditoria? auditoria}) => Plan(
  id: p.id,
  clubId: p.clubId,
  name: p.name,
  type: p.type,
  weekModels: weekModels ?? p.weekModels,
  weekAssignment: p.weekAssignment,
  published: published ?? p.published,
  auditoria: auditoria ?? p.auditoria,
);

class _PlanWrites implements CreatePlanStore, SavePlanStore, PublishPlanStore {
  _PlanWrites(this.db);

  final _Db db;

  @override
  Future<void> insert(Plan plan) async {
    db.planWrites++;
    if (db.plans.containsKey(plan.id)) throw StateError('duplicate _id ${plan.id}');
    db.plans[plan.id] = plan;
  }

  @override
  Future<Plan?> plan(String clubId, String planId) async {
    final p = db.plans[planId];
    return p?.clubId == clubId ? p : null;
  }

  @override
  Future<Map<String, Exercise>> exercises(String clubId) async => db.visible(clubId);

  @override
  Future<bool> replace(Plan plan) async {
    db.planWrites++;
    final stored = db.plans[plan.id];
    if (stored == null) return false;
    db.plans[plan.id] = _with(plan, published: stored.published);
    return true;
  }

  @override
  Future<bool> publish(String clubId, String planId, PublishedPlan copy, {required DateTime? savedAt}) async {
    db.planWrites++;
    final stored = db.plans[planId];
    if (stored == null || stored.auditoria.modificadoEn != savedAt) return false;
    db.plans[planId] = _with(stored, published: copy);
    return true;
  }
}

Exercise _base(String id, String name, List<String> categories, List<Metric> metrics) => Exercise(
  id: id,
  clubId: clubPlataforma,
  name: name,
  categoryIds: categories,
  metrics: metrics,
  defaultMetric: metrics.first,
  loadReference: metrics.contains(Metric.loadPctRm) && id != 'sq_espalda'
      ? const LoadReference.otherExercise('sq_espalda')
      : (id == 'sq_espalda' ? const LoadReference.own() : const LoadReference.none()),
  auditoria: _audit,
);

/// A small base catalog in the shape of the E2.7 seed (invented, not the real list).
_Db _seeded() {
  final db = _Db();
  for (final c in ['primario', 'secundario', 'accesorio', 'calentamiento', 'estiramiento', 'wod']) {
    db.categories.add(Category(id: c, clubId: clubPlataforma, name: c, auditoria: _audit));
  }
  const load = [Metric.loadPctRm, Metric.reps];
  db.exercises.addAll([
    _base('sq_espalda', 'Sentadilla', ['primario'], load),
    _base('sq_zercher', 'Sentadilla Zercher', ['primario'], load),
    _base('hip_thrust', 'Hip thrust', ['secundario'], load),
    _base('row_x', 'Remo inventado', ['accesorio'], const [Metric.fixedLoad, Metric.reps]),
    _base('est_sq', 'Estiramiento de sentadilla', ['estiramiento'], const [Metric.time]),
    _base('est_bp', 'Estiramiento de bench', ['estiramiento'], const [Metric.time]),
  ]);
  db.timers.add(
    const Temporizador(id: 'desc_120', nombre: 'Descanso 2 min', tipo: TipoTemporizador.countdown, trabajoSeg: 120),
  );
  return db;
}

// Invented rows: the real spreadsheet is personal data and never enters the repo.
const _sheets = {
  'Ejercicios': '''
id,nombre,categoria,referencia,notas,medida,inactivo
sq_espalda,Back squat,primario,sentadilla,basico,,
hip_thrust,Hip thrust,secundario,peso_muerto,,,
curl_x,Curl inventado,accesorio,,,,
cal_x,Calentamiento inventado,calentamiento,,,reps,
est_sq,Estiramiento sentadilla,estiramiento,sentadilla,,tiempo,
est_libre,Estiramiento libre,estiramiento,,,tiempo,
est_bp,Estiramiento bench,estiramiento,bench,,tiempo,
''',
  'Temporizadores': '''
id,nombre,tipo,trabajo_seg,descanso_seg,rondas
desc_120,Descanso 2 min,countdown,120,,
''',
  'WoDs': 'id,nombre,formato,temporizador,descripcion\n',
  'Planes': '''
id,nombre,activo,inicio,secuencia
plan_viejo,Viejo ,TRUE,2026-10-01,
plan_nuevo,Nuevo,FALSE,2026-11-03,"a,b,b,a"
''',
  'PlanModelos': '''
plan,id,nombre,archivado
plan_nuevo,a,Descarga,FALSE
plan_nuevo,b,Carga,FALSE
plan_nuevo,z,Vieja,TRUE
''',
  'PlanDias': '''
plan,dia,primario,estiramiento,calentamiento
plan_viejo,1,sq_espalda,,"cal_x, cal_borrado"
plan_nuevo,1,sq_espalda,est_bp,
''',
  'PlanEjercicios': '''
plan,dia,bloque,grupo,orden,ejercicio,variante,serie,reps,pct,rpe,temporizador
plan_viejo,1,principal,,1,sq_espalda,descarga,1,8,25,6,desc_120
plan_viejo,1,principal,,1,sq_espalda,descarga,2,5,50,6,desc_120
plan_viejo,1,principal,,1,sq_espalda,descarga,3,3,80,6,desc_120
plan_viejo,1,principal,,1,sq_espalda,carga,2,5,55,8 - 9,desc_120
plan_viejo,1,principal,,1,sq_espalda,carga,1,8,25,8 - 9,desc_120
plan_viejo,1,principal,,1,sq_espalda,carga,3,3,85,8 - 9,desc_120
plan_viejo,1,principal,,1,sq_espalda,carga,4,3,85,8 - 9,desc_120
plan_viejo,1,principal,,2,sq_zercher,carga,1,5,60,,
plan_viejo,1,principal,,2,hip_thrust,carga,1,8,,2026-06-07,
plan_viejo,1,final,1,1,row_x,carga,1,12,,,
plan_viejo,1,final,1,2,curl_x,carga,1,10,,,
plan_viejo,1,final,2,1,curl_x,carga,1,10,,,
plan_viejo,1,final,2,2,no_existe,carga,1,10,,,
plan_nuevo,1,calentamiento,,1,cal_x,a,1,10,,,
plan_nuevo,1,principal,,1,sq_espalda,a,1,8,60,,desc_120
plan_nuevo,1,principal,,1,sq_espalda,b,1,8,65,,desc_120
plan_nuevo,1,final,1,1,row_x,b,1,12,,,
''',
  'PlanWods': 'plan,dia,variante,wod\n',
};

final _adjustments = ImportAdjustments.fromJson({
  'plans': {
    'pctCorrections': [
      {'plan': 'plan_viejo', 'from': 85, 'to': 80},
    ],
  },
});

void main() {
  late Directory dir;
  late _Db db;

  void write(String sheet, String csv) => File('${dir.path}/$sheet.csv').writeAsStringSync(csv.trimLeft());

  setUp(() {
    dir = Directory.systemTemp.createTempSync('plan_import_test');
    _sheets.forEach(write);
    db = _seeded();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  final now = DateTime.utc(2026, 11, 14);
  CatalogImport catalog() => CatalogImport(
    reads: _CatalogStores(db),
    exerciseWrites: _CatalogStores(db),
    timerWrites: _CatalogStores(db),
    wodWrites: _CatalogStores(db),
    now: () => now,
  );
  PlanImport importer() => PlanImport(
    catalog: catalog(),
    reads: _PlanReads(db),
    creates: _PlanWrites(db),
    saves: _PlanWrites(db),
    publishes: _PlanWrites(db),
    now: () => now,
  );
  ImportRun run({bool dryRun = false, ImportAdjustments? adjustments}) => ImportRun(
    club: importClubContext(_club, TipoClub.club),
    sheets: SheetDirectory(dir.path),
    adjustments: adjustments ?? _adjustments,
    dryRun: dryRun,
  );
  Future<void> importCatalog() => catalog().run(run());

  Plan plan(String sheetId) => db.plans[importedId(_club, sheetId)]!;
  String own(String sheetId) => importedId(_club, sheetId);
  List<String?> exercisesOf(PlanBlock b) => [for (final p in b.prescriptions) p.exerciseId];

  test('a plan without secuencia gets the legacy variants as week models', () async {
    await importCatalog();
    await importer().run(run());
    final p = plan('plan_viejo');
    expect(p.name, 'Viejo');
    expect([for (final m in p.weekModels) (m.id, m.name)], [('descarga', 'Descarga'), ('carga', 'Carga')]);
    expect(p.weekAssignment, ['descarga', 'carga', 'carga', 'descarga'], reason: 'no carga2: week 3 repeats carga');
  });

  test('the blocks of a day follow the old app, each with the category of its exercises', () async {
    await importCatalog();
    await importer().run(run());
    final day = plan('plan_viejo').weekModelOf(2)!.days.single;
    expect(
      [for (final b in day.blocks) (b.name, b.categoryId, b.executionMode)],
      [
        ('Estiramiento', 'estiramiento', ExecutionMode.sequential),
        ('Calentamiento', 'calentamiento', ExecutionMode.sequential),
        ('Primario', 'primario', ExecutionMode.sequential),
        ('Secundario', 'secundario', ExecutionMode.sequential),
        ('Biserie', 'accesorio', ExecutionMode.circuit),
        ('Accesorios', 'accesorio', ExecutionMode.sequential),
      ],
    );
    // Automatic stretches of the primary's reference (or none); the warm-up list keeps what exists.
    expect(exercisesOf(day.blocks[0]), ['est_sq', own('est_libre')]);
    expect(day.blocks[0].prescriptions.first.sets, isEmpty);
    expect(exercisesOf(day.blocks[1]), [own('cal_x')]);
    // A primary-only exercise used as second lift stays in the primary block.
    expect(exercisesOf(day.blocks[2]), ['sq_espalda', 'sq_zercher']);
    expect(exercisesOf(day.blocks[3]), ['hip_thrust']);
    expect(exercisesOf(day.blocks[4]), ['row_x', own('curl_x')]);
    expect(exercisesOf(day.blocks[5]), [own('curl_x')], reason: 'the unknown exercise of group 2 is dropped');
  });

  test('sets, RPE and timer come from the rows, ordered by serie', () async {
    await importCatalog();
    final report = await importer().run(run());
    final squat = plan('plan_viejo').weekModelOf(2)!.days.single.blocks[2].prescriptions.first;
    expect([for (final s in squat.sets) s.reps], [8, 5, 3, 3]);
    expect(squat.note, 'RPE 8 - 9');
    expect(squat.timerId, 'desc_120');
    expect(squat.barKg, isNull);
    final hip = plan('plan_viejo').weekModelOf(2)!.days.single.blocks[3].prescriptions.single;
    expect(hip.note, 'RPE 6 - 7', reason: 'the sheet turned "6-7" into a date');
    expect(report.notes, contains(contains('2026-06-07')));
    expect(report.problems, [contains('"no_existe"')]);
    expect(report.notes, contains(contains('"cal_borrado"')));
  });

  test('October: 85 becomes 80 and the ramp below moves with it; the bar set stays', () async {
    await importCatalog();
    final report = await importer().run(run());
    final p = plan('plan_viejo');
    List<double?> pcts(int week) => [
      for (final s in p.weekModelOf(week)!.days.single.blocks[2].prescriptions.first.sets) s.pct,
    ];
    expect(pcts(2), [25, 52.5, 80, 80]);
    expect(pcts(1), [25, 50, 80], reason: 'no 85 there');
    expect(report.notes, contains(contains('85 % → 80 %')));
    expect(plan('plan_nuevo').weekModelOf(2)!.days.single.blocks[1].prescriptions.first.sets.single.pct, 65);
  });

  test('a plan with PlanModelos and secuencia maps them one to one and is published when complete', () async {
    await importCatalog();
    final report = await importer().run(run());
    final p = plan('plan_nuevo');
    expect([for (final m in p.weekModels) m.id], ['a', 'b'], reason: 'archived and unused: left out');
    expect(p.weekAssignment, ['a', 'b', 'b', 'a']);
    expect(p.published, isNotNull);
    expect(
      jsonEncode([for (final m in p.published!.weekModels) m.toJson()]),
      jsonEncode([for (final m in p.weekModels) m.toJson()]),
    );
    final a = p.weekModelOf(1)!.days.single;
    expect([for (final b in a.blocks) b.name], ['Estiramiento', 'Calentamiento', 'Primario']);
    expect(exercisesOf(a.blocks[0]), ['est_bp'], reason: 'the PlanDias stretch wins over the automatic ones');
    expect([for (final b in p.weekModelOf(2)!.days.single.blocks) b.name], ['Estiramiento', 'Primario', 'Accesorios']);

    expect(plan('plan_viejo').published, isNull, reason: 'a secondary without % cannot be published');
    expect(report.notes, contains(allOf(contains('"Viejo"'), contains('borrador'), contains('setWithoutPct'))));
    expect(report.notes, contains(allOf(contains('activo=sí'), contains('E6'))));
  });

  test('running twice changes nothing; a plan changed in the app is reported and left alone', () async {
    await importCatalog();
    await importer().run(run());
    final writes = db.planWrites;
    final before = jsonEncode({for (final e in db.plans.entries) e.key: e.value.toJson()});

    final again = await importer().run(run());
    expect(db.planWrites, writes);
    expect(jsonEncode({for (final e in db.plans.entries) e.key: e.value.toJson()}), before);
    expect(again.created, isEmpty);
    expect(again.unchanged, hasLength(2));

    final edited = plan('plan_nuevo');
    db.plans[edited.id] = _with(edited, weekModels: [edited.weekModels.first]);
    final third = await importer().run(run());
    expect(third.differing.single, contains('plan_nuevo'));
    expect(db.plans[edited.id]!.weekModels, hasLength(1));
  });

  ImportAdjustments withFills(List<Map<String, Object?>> fills) => ImportAdjustments.fromJson({
    'plans': {...(_adjustments.raw['plans'] as Map), 'pctFills': fills},
  });
  const hipFill = {'plan': 'plan_viejo', 'variante': 'carga', 'dia': 1, 'bloque': 'principal', 'orden': 2};

  test('the sets missing a % are listed; a pctFills value later completes and publishes the draft', () async {
    await importCatalog();
    final first = await importer().run(run());
    final listed = (await importer().plan(run())).missingPct['plan_viejo']!;
    expect([for (final r in listed) (r.variant, r.exercise, r.set)], [('carga', 'hip_thrust', 1)]);
    expect(
      first.notes,
      contains(allOf(contains('faltan 1 %'), contains('"hip_thrust", serie 1'), contains('semanas 2, 3'))),
    );
    expect(plan('plan_viejo').published, isNull);

    final adjustments = withFills([
      {...hipFill, 'ejercicio': 'hip_thrust', 'serie': 1, 'pct': 70},
    ]);
    final second = await importer().run(run(adjustments: adjustments));
    expect(second.updated.single, allOf(contains('plan_viejo'), contains('se publica')));
    final hip = plan('plan_viejo').published!.weekModels[1].days.single.blocks[3].prescriptions.single;
    expect(hip.sets.single.pct, 70);
    final third = await importer().run(run(adjustments: adjustments));
    expect(third.unchanged, hasLength(2), reason: 'published now: a re-run changes nothing');
  });

  test('a fill with no value keeps the draft; a fill on a row with a % or on no row is reported', () async {
    await importCatalog();
    final report = await importer().run(
      run(
        adjustments: withFills([
          {...hipFill, 'ejercicio': 'hip_thrust', 'serie': 1, 'pct': null},
          {
            'plan': 'plan_viejo',
            'variante': 'carga',
            'dia': 1,
            'bloque': 'principal',
            'orden': 1,
            'ejercicio': 'sq_espalda',
            'serie': 1,
            'pct': 30,
          },
          {...hipFill, 'ejercicio': 'hip_thrust', 'serie': 9, 'pct': 70},
        ]),
      ),
    );
    expect(plan('plan_viejo').published, isNull);
    expect(report.notes, contains(contains('1 siguen sin valor')));
    expect(report.problems, contains(allOf(contains('"sq_espalda"'), contains('ya tiene'))));
    expect(report.problems, contains(allOf(contains('serie 9'), contains('no hay una fila'))));
  });

  test('a draft edited in the app is never overwritten by a fill', () async {
    await importCatalog();
    await importer().run(run());
    final p = plan('plan_viejo');
    db.plans[p.id] = _with(p, auditoria: p.auditoria.modificada('coach-1', ahora: now));
    final report = await importer().run(
      run(
        adjustments: withFills([
          {...hipFill, 'ejercicio': 'hip_thrust', 'serie': 1, 'pct': 70},
        ]),
      ),
    );
    expect(report.differing.single, contains('plan_viejo'));
    expect(plan('plan_viejo').published, isNull);
  });

  test('a plan saved but not published (a cut run) is published by the next run', () async {
    await importCatalog();
    await importer().run(run());
    final p = plan('plan_nuevo');
    db.plans[p.id] = Plan(
      id: p.id,
      clubId: p.clubId,
      name: p.name,
      weekModels: p.weekModels,
      weekAssignment: p.weekAssignment,
      auditoria: p.auditoria,
    );
    final report = await importer().run(run());
    expect(report.updated.single, contains('se publica'));
    expect(plan('plan_nuevo').published, isNotNull);
  });

  test('a dry run writes nothing, even before the catalog is imported', () async {
    final report = await importer().run(run(dryRun: true));
    expect(db.plans, isEmpty);
    expect(report.created, hasLength(2));
    expect(report.created.last, contains('se publica'), reason: 'it sees the catalog as the catalog step leaves it');
  });

  test('applying before the catalog step writes no plan', () async {
    final report = await importer().run(run());
    expect(db.plans, isEmpty);
    expect(report.problems, contains(contains('"catalogo"')));
  });

  test('locate tells the history import where a Registro row landed', () async {
    await importCatalog();
    final result = await importer().plan(run());
    final squat = result.locate(
      sheetPlanId: 'plan_viejo',
      variant: 'carga',
      day: 1,
      block: 'principal',
      order: 1,
      exercise: 'sq_espalda',
    )!;
    expect((squat.weekModelId, squat.dayIndex, squat.blockIndex, squat.prescriptionIndex), ('carga', 0, 2, 0));
    expect(squat.setIndexOf(4), 3);
    final curl = result.locate(
      sheetPlanId: 'plan_viejo',
      variant: 'Carga',
      day: 1,
      block: 'final',
      group: '2',
      order: 1,
      exercise: 'curl_x',
    )!;
    expect((curl.blockIndex, curl.prescriptionIndex), (5, 0));
    final stretch = result.locate(
      sheetPlanId: 'plan_viejo',
      variant: 'descarga',
      day: 1,
      block: 'estiramiento',
      exercise: 'est_libre',
    )!;
    expect((stretch.blockIndex, stretch.prescriptionIndex), (0, 1));
    expect(stretch.setNumbers, isEmpty);
    expect(
      result.locate(
        sheetPlanId: 'plan_viejo',
        variant: 'carga2',
        day: 1,
        block: 'principal',
        order: 1,
        exercise: 'sq_espalda',
      ),
      isNull,
    );
  });

  test('a row of PlanWods is reported, not dropped silently', () async {
    write('PlanWods', 'plan,dia,variante,wod\nplan_nuevo,1,a,wod_x\n');
    await importCatalog();
    final report = await importer().run(run());
    expect(report.problems, contains(contains('WoDs')));
  });
}
