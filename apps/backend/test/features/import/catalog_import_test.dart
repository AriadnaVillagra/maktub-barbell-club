import 'dart:convert';
import 'dart:io';

import 'package:maktub_backend/features/catalogo/create_timer/create_timer_store.dart';
import 'package:maktub_backend/features/catalogo/write_exercise/write_exercise_store.dart';
import 'package:maktub_backend/features/import/adjustments.dart';
import 'package:maktub_backend/features/import/catalog/catalog_import.dart';
import 'package:maktub_backend/features/import/catalog/catalog_import_store.dart';
import 'package:maktub_backend/features/import/import_run.dart';
import 'package:maktub_backend/features/import/sheets.dart';
import 'package:maktub_backend/features/wods/crear/crear_store.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

/// Every store the import touches, over one in-memory catalog.
class _FakeDb implements CatalogImportStore, WriteExerciseStore, CreateTimerStore, CreateWodStore {
  final exercises = <Exercise>[];
  final categories = <Category>[];
  final timerList = <Temporizador>[];
  final wodList = <Wod>[];
  var writes = 0;

  @override
  Future<CatalogView> view(Set<String> clubIds) async => CatalogView.of(
    exercises: exercises.where((e) => clubIds.contains(e.clubId)),
    categories: categories.where((c) => clubIds.contains(c.clubId)),
  );

  @override
  Future<List<Temporizador>> timers(Set<String> clubIds) async =>
      timerList.where((t) => clubIds.contains(t.clubId)).toList();

  @override
  Future<List<Wod>> wods(String clubId) async => wodList.where((w) => w.clubId == clubId).toList();

  @override
  Future<void> insert(Object item) async {
    writes++;
    switch (item) {
      case final Exercise e:
        if (exercises.any((x) => x.id == e.id)) throw StateError('duplicate _id ${e.id}');
        exercises.add(e);
      case final Temporizador t:
        timerList.add(t);
      case final Wod w:
        wodList.add(w);
    }
  }

  @override
  Future<void> replace(Exercise exercise) async {
    writes++;
    final i = exercises.indexWhere((e) => e.id == exercise.id && e.clubId == exercise.clubId);
    exercises[i] = exercise;
  }

  @override
  Future<void> delete(String clubId, String id) => throw UnimplementedError();

  String snapshot() => jsonEncode({
    'exercises': [for (final e in exercises) e.toJson()],
    'timers': [for (final t in timerList) t.toJson()],
    'wods': [for (final w in wodList) w.toJson()],
  });
}

const _club = 'club1';
final _audit = Auditoria.nueva('sistema:semilla', ahora: DateTime.utc(2026, 11, 7));

Exercise _base(String id, String name, List<String> categories, {LoadReference ref = const LoadReference.none()}) =>
    Exercise(
      id: id,
      clubId: clubPlataforma,
      name: name,
      categoryIds: categories,
      metrics: const [Metric.loadPctRm, Metric.reps],
      defaultMetric: Metric.loadPctRm,
      loadReference: ref,
      auditoria: _audit,
    );

/// A small base catalog in the shape of the E2.7 seed (invented, not the real list).
_FakeDb _seeded() {
  final db = _FakeDb();
  for (final c in ['primario', 'secundario', 'accesorio', 'calentamiento', 'estiramiento', 'wod']) {
    db.categories.add(Category(id: c, clubId: clubPlataforma, name: c, auditoria: _audit));
  }
  db.exercises.addAll([
    _base('sq_espalda', 'Sentadilla de espalda', ['primario'], ref: const LoadReference.own()),
    _base('bp_plano', 'Bench press', ['primario'], ref: const LoadReference.own()),
    _base('dl_convencional', 'Peso muerto', ['primario'], ref: const LoadReference.own()),
    _base('dumbbell_row', 'Remo con mancuerna', ['accesorio']),
    _base('plank', 'Plancha', ['accesorio']),
    _base('cal_sq', 'Movilidad de cadera y tobillo', ['calentamiento']),
    _base('skull', 'Press francés', ['accesorio']),
  ]);
  db.timerList.addAll(const [
    Temporizador(id: 'desc_90', nombre: 'Descanso 1:30', tipo: TipoTemporizador.countdown, trabajoSeg: 90),
    Temporizador(id: 'cuenta_5', nombre: 'Cuenta regresiva 5 min', tipo: TipoTemporizador.countdown, trabajoSeg: 300),
    Temporizador(id: 'cronometro', nombre: 'Cronómetro', tipo: TipoTemporizador.forTime),
  ]);
  return db;
}

// Invented rows: the real spreadsheet is personal data and never enters the repo.
const _exercisesCsv = '''
id,nombre,categoria,referencia,notas,medida,inactivo,columna_nueva
sq_espalda,Back squat,primario,sentadilla,basico,peso,,z
sq_box,Box squat,secundario,sentadilla,variante,,,
curl_x,Curl inventado,accesorio,,brazos,,,
hollow,Hollow,calentamiento,,Abdominales,reps,,
plancha,Plancha,calentamiento,,Abdominales,tiempo,,
cal_sq,Sit ups,calentamiento,,,reps,,
est_x,Estiramiento inventado,estiramiento,bench,,,,
viejo,Ejercicio viejo,accesorio,,,,x,
bird,Bird dog,calentamiento,,Abdominales,reps,,
bird,Bird dog 2,accesorio,,,,,
skull_crushers,Skull crushers,accesorio,,,,,
raro,Raro,inventada,,,,,
''';

const _timersCsv = '''
id,nombre,tipo,trabajo_seg,descanso_seg,rondas
desc_90,Descanso 1:30,countdown,90,,
desc_45,Descanso 45 s,countdown,45,,
cuenta_5,Cuenta regresiva 5 min,countdown,240,,
''';

const _wodsCsv = '''
id,nombre,formato,temporizador,descripcion
wod_a,AMRAP 5,amrap,cuenta_5,"Hasta el final, sin parar."
wod_f,For time inventado,for_time,,21-15-9
wod_d,Con descanso,amrap,desc_45,
''';

const _adjustments = ImportAdjustments(
  exercises: ExerciseAdjustments(notBase: {'cal_sq'}, sameAs: {'skull_crushers': 'skull'}),
);

void main() {
  late Directory dir;
  late _FakeDb db;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('catalog_import_test');
    File('${dir.path}/Ejercicios.csv').writeAsStringSync(_exercisesCsv.trimLeft());
    File('${dir.path}/Temporizadores.csv').writeAsStringSync(_timersCsv.trimLeft());
    File('${dir.path}/WoDs.csv').writeAsStringSync(_wodsCsv.trimLeft());
    db = _seeded();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  CatalogImport importer() => CatalogImport(
    reads: db,
    exerciseWrites: db,
    timerWrites: db,
    wodWrites: db,
    now: () => DateTime.utc(2026, 11, 14),
  );

  ImportRun run({bool dryRun = false}) => ImportRun(
    club: importClubContext(_club, TipoClub.club),
    sheets: SheetDirectory(dir.path),
    adjustments: _adjustments,
    dryRun: dryRun,
  );

  Exercise exercise(String id) => db.exercises.singleWhere((e) => e.id == id);
  String own(String sheetId) => importedId(_club, sheetId);

  test('creates the club exercises with the measure and reference of the old app', () async {
    final report = await importer().run(run());
    expect(report.problems.single, contains('Raro'));

    final box = exercise(own('sq_box'));
    expect(box.clubId, _club);
    expect(box.categoryIds, ['secundario']);
    expect(box.loadReference, const LoadReference.otherExercise('sq_espalda'));
    expect(box.metrics, [Metric.loadPctRm, Metric.reps]);
    expect(box.notes, isNull, reason: '"variante" only classified primaries');
    expect(box.auditoria.creadoPor, importAuthor);

    final curl = exercise(own('curl_x'));
    expect(curl.metrics, [Metric.fixedLoad, Metric.reps]);
    expect((curl.loadReference.kind, curl.notes), (LoadReferenceKind.none, 'brazos'));
    expect(exercise(own('hollow')).metrics, [Metric.reps]);
    final stretch = exercise(own('est_x'));
    expect(stretch.loadReference.kind, LoadReferenceKind.none);
    expect(stretch.suggestionIds, ['bp_plano']);
    expect(exercise(own('viejo')).status, CatalogStatus.archived);
  });

  test('an exercise of the seed is not duplicated: it only gains the sheet category', () async {
    await importer().run(run());
    expect(db.exercises.where((e) => normalizeName(e.name) == 'plancha'), hasLength(1));
    expect(exercise('plank').categoryIds, ['accesorio', 'calentamiento']);
    expect(exercise('plank').auditoria.modificadoPor, importAuthor);
    final squat = exercise('sq_espalda');
    expect(squat.name, 'Sentadilla de espalda');
    expect(squat.categoryIds, ['primario']);
    expect(db.exercises.where((e) => e.id == own('sq_espalda')), isEmpty);
  });

  test('adjustments: notBase becomes a club exercise, sameAs joins the default one', () async {
    await importer().run(run());
    expect(exercise(own('cal_sq')).name, 'Sit ups');
    expect(exercise('cal_sq').name, 'Movilidad de cadera y tobillo');
    expect(db.exercises.where((e) => e.id == own('skull_crushers')), isEmpty);
    expect(exercise('skull').categoryIds, ['accesorio']);
  });

  test('rows repeating an id become one exercise with both categories', () async {
    final report = await importer().run(run());
    final bird = exercise(own('bird'));
    expect((bird.name, bird.notes), ('Bird dog 2', 'Abdominales'));
    expect(bird.categoryIds, ['calentamiento', 'accesorio']);
    expect(bird.metrics, [Metric.reps], reason: 'an empty medida does not override an explicit one');
    expect(report.notes.first, contains('"bird" se repite'));
  });

  test('timers match the default ones by id; a new one goes to the club; a different one is reported', () async {
    final report = await importer().run(run());
    expect(db.timerList.map((t) => t.id), ['desc_90', 'cuenta_5', 'cronometro', own('desc_45')]);
    expect(db.timerList.last.clubId, _club);
    expect(db.timerList.firstWhere((t) => t.id == 'cuenta_5').trabajoSeg, 300, reason: 'never overwritten');
    expect(report.differing.single, contains('cuenta_5'));
  });

  test('WoDs go to the club library with their timer resolved', () async {
    await importer().run(run());
    final byName = {for (final w in db.wodList) w.name: w};
    expect(byName.keys, ['AMRAP 5', 'For time inventado', 'Con descanso']);
    expect(byName['AMRAP 5']!.id, own('wod_a'));
    expect(byName['AMRAP 5']!.timerId, 'cuenta_5');
    expect(byName['AMRAP 5']!.description, 'Hasta el final, sin parar.');
    expect(byName['For time inventado']!.timerId, 'cronometro');
    expect(byName['Con descanso']!.timerId, own('desc_45'));
    expect(db.wodList.every((w) => w.clubId == _club && w.prescriptions.isEmpty), isTrue);
  });

  test('running it twice leaves the same catalog as running it once', () async {
    await importer().run(run());
    final once = db.snapshot();
    final writes = db.writes;

    final second = await importer().run(run());
    expect(db.snapshot(), once);
    expect(db.writes, writes);
    expect(second.created, isEmpty);
    expect(second.updated, isEmpty);
  });

  test('a dry run reports the same as a real run and writes nothing', () async {
    final before = db.snapshot();
    final dry = await importer().run(run(dryRun: true));
    expect(db.snapshot(), before);
    expect(db.writes, 0);

    final real = await importer().run(run());
    expect(dry.created, real.created);
    expect(dry.updated, real.updated);
  });

  test('an exercise created in the app with the same name is reused, not duplicated', () async {
    db.exercises.add(
      Exercise(id: 'abc', clubId: _club, name: 'hollow', categoryIds: const ['accesorio'], auditoria: _audit),
    );
    await importer().run(run());
    expect(db.exercises.where((e) => normalizeName(e.name) == 'hollow').single.categoryIds, [
      'accesorio',
      'calentamiento',
    ]);
  });

  test('the plan resolves any sheet exercise id for the later steps', () async {
    await importer().run(run());
    final plan = await importer().plan(run(dryRun: true));
    expect(plan.isEmpty, isTrue);
    expect(plan.exerciseIdFor('plancha'), 'plank');
    expect(plan.exerciseIdFor('cal_sq'), own('cal_sq'));
    expect(plan.exerciseIdFor('dumbbell_row'), 'dumbbell_row', reason: 'used by plans, missing from Ejercicios');
    expect(plan.exerciseIdFor('bench'), 'bp_plano', reason: 'RMs name the basic lifts');
    expect(plan.exerciseIdFor('nada'), isNull);
  });
}
