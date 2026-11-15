import 'dart:convert';
import 'dart:io';

import 'package:maktub_backend/features/import/adjustments.dart';
import 'package:maktub_backend/features/import/athletes/athlete_import.dart';
import 'package:maktub_backend/features/import/athletes/athlete_import_store.dart';
import 'package:maktub_backend/features/import/import_run.dart';
import 'package:maktub_backend/features/import/sheets.dart';
import 'package:maktub_backend/features/kilajes/fijar_kilaje/fijar_kilaje_store.dart';
import 'package:maktub_backend/features/referencias/registrar_rm/registrar_rm_store.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

/// Every store the step touches, over one in-memory club.
class _FakeDb implements AthleteImportStore, RegisterRmStore, SetFixedWeightStore {
  final athleteList = <Atleta>[];
  final references = <Reference>[];
  final weights = <FixedWeight>[];
  final exercises = <String>{'sq_espalda', 'bp_plano', 'dl_convencional', 'curl_x', 'remo_x'};
  var writes = 0;

  @override
  Future<List<Atleta>> athletes(String clubId) async => athleteList.where((a) => a.clubId == clubId).toList();

  @override
  Future<List<Reference>> rms(String clubId) async =>
      references.where((r) => r.clubId == clubId && r.type == ReferenceType.rm).toList();

  @override
  Future<List<FixedWeight>> fixedWeights(String clubId) async => weights.where((w) => w.clubId == clubId).toList();

  @override
  Future<bool> athleteInClub(String clubId, String athleteId) async =>
      athleteList.any((a) => a.id == athleteId && a.clubId == clubId);

  @override
  Future<bool> exerciseVisible(String clubId, String exerciseId) async => exercises.contains(exerciseId);

  @override
  Future<void> insert(Reference reference) async {
    writes++;
    if (references.any((r) => r.id == reference.id)) throw StateError('duplicate _id ${reference.id}');
    references.add(reference);
  }

  @override
  Future<FixedWeight?> find(String clubId, String athleteId, String exerciseId) async =>
      weights.where((w) => w.clubId == clubId && w.athleteId == athleteId && w.exerciseId == exerciseId).firstOrNull;

  @override
  Future<void> save(FixedWeight weight) async {
    writes++;
    weights
      ..removeWhere(
        (w) => w.clubId == weight.clubId && w.athleteId == weight.athleteId && w.exerciseId == weight.exerciseId,
      )
      ..add(weight);
  }

  String snapshot() => jsonEncode({
    'references': [for (final r in references) r.toJson()],
    'weights': [for (final w in weights) w.toJson()],
  });
}

const _club = 'club1';
final _audit = Auditoria.nueva('sistema:alta', ahora: DateTime.utc(2026, 11, 7));

Atleta _athlete(String id, String name, {String club = _club}) =>
    Atleta(id: id, clubId: club, usuarioId: 'u-$id', nombreVisible: name, auditoria: _audit);

// Invented rows and names: the real spreadsheet is personal data and never enters the repo.
const _athletesCsv = '''
id,nombre
x1,Martina Pérez
x2,Joaquín
x3,Nadie
''';

const _rmsCsv = '''
atleta,ejercicio,kilos,fecha
x1,sentadilla,70,2026-03-01
x1,bench,"52,5",2026-03-01
x2,sentadilla,80,2026-03-01
x2,sentadilla,90,2026-09-01
x2,sentadilla,92,2026-09-01
x1,peso_muerto,0,2026-03-01
x1,peso_muerto,95,1/3/2026
x3,sentadilla,60,2026-03-01
x9,sentadilla,60,2026-03-01
x1,inventado,40,2026-03-01
''';

const _weightsCsv = '''
atleta,ejercicio,kilos
x1,curl_x,18
x1,remo_x,12
x2,curl_x,15
x2,curl_x,16
x1,remo_x,abc
''';

/// The catalog as E8.2 resolves it: basic lift keys and sheet ids to app exercises.
String? _exerciseIdFor(String sheetId) => const {
  'sentadilla': 'sq_espalda',
  'bench': 'bp_plano',
  'peso_muerto': 'dl_convencional',
  'curl_x': 'curl_x',
  'remo_x': 'remo_x',
}[sheetId];

const _adjustments = {
  'athletes': {
    'sameAs': {'x1': 'Marti'},
    'testedRmDates': ['2026-03-01'],
  },
};

void main() {
  late Directory dir;
  late _FakeDb db;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('athlete_import_test');
    File('${dir.path}/Atletas.csv').writeAsStringSync(_athletesCsv.trimLeft());
    File('${dir.path}/RMs.csv').writeAsStringSync(_rmsCsv.trimLeft());
    File('${dir.path}/PesosAccesorios.csv').writeAsStringSync(_weightsCsv.trimLeft());
    db = _FakeDb()
      ..athleteList.addAll([
        _athlete('ath-m', 'Marti'),
        _athlete('ath-j', 'joaquin'),
        // The same person's athlete in a personal club: never a match.
        _athlete('ath-j-personal', 'Joaquín', club: 'personal'),
      ]);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  AthleteImport importer() => AthleteImport(
    reads: db,
    exercises: (_) async => _exerciseIdFor,
    rmWrites: db,
    weightWrites: db,
    now: () => DateTime.utc(2026, 11, 14),
  );

  ImportRun run({bool dryRun = false, Map<String, dynamic> adjustments = _adjustments}) => ImportRun(
    club: importClubContext(_club, TipoClub.club),
    sheets: SheetDirectory(dir.path),
    adjustments: ImportAdjustments.fromJson(adjustments),
    dryRun: dryRun,
  );

  Reference rm(String athleteId, String exerciseId, DateTime date) =>
      db.references.singleWhere((r) => r.athleteId == athleteId && r.exerciseId == exerciseId && r.date == date);

  test('matches sheet athletes by adjustment or by name, only within the club', () async {
    final plan = await importer().plan(run(dryRun: true));
    expect(plan.athleteIdFor('x1'), 'ath-m', reason: 'sameAs');
    expect(plan.athleteIdFor('x2'), 'ath-j', reason: 'same name ignoring case and accents');
    expect(plan.athleteIdFor('x3'), isNull);
    expect(plan.report.problems, contains(contains('atleta x3 (Atletas línea 4)')));
  });

  test('every RM row becomes a reference of its athlete; the test dates are testeado', () async {
    final report = await importer().run(run());
    final squat = rm('ath-m', 'sq_espalda', DateTime.utc(2026, 3, 1));
    expect((squat.value, squat.origin, squat.type), (70.0, ReferenceOrigin.testeado, ReferenceType.rm));
    expect(squat.id, importedId(_club, 'rm-x1-sentadilla-2026-03-01'));
    expect(squat.auditoria.creadoPor, importAuthor);
    expect(rm('ath-m', 'bp_plano', DateTime.utc(2026, 3, 1)).value, 52.5, reason: 'decimal comma');
    expect(rm('ath-j', 'sq_espalda', DateTime.utc(2026, 3, 1)).origin, ReferenceOrigin.testeado);

    final later = rm('ath-j', 'sq_espalda', DateTime.utc(2026, 9, 1));
    expect((later.value, later.origin), (92.0, ReferenceOrigin.importado), reason: 'the last repeated row wins');
    expect(report.notes, contains(contains('RMs línea 6 repite')));
    expect(db.references, hasLength(4));
  });

  test('every PesosAccesorios row becomes the fixed weight of its athlete', () async {
    await importer().run(run());
    final byKey = {for (final w in db.weights) (w.athleteId, w.exerciseId): w.kg};
    expect(byKey, {('ath-m', 'curl_x'): 18.0, ('ath-m', 'remo_x'): 12.0, ('ath-j', 'curl_x'): 16.0});
    final curl = db.weights.firstWhere((w) => w.athleteId == 'ath-m' && w.exerciseId == 'curl_x');
    expect(curl.id, importedId(_club, 'kilaje-x1-curl_x'));
  });

  test('rows that cannot be imported are reported, and the others go in', () async {
    final report = await importer().run(run());
    String problemAt(String where) => report.problems.singleWhere((p) => p.startsWith(where));
    expect(problemAt('RMs línea 8'), contains('fecha "1/3/2026"'));
    expect(problemAt('RMs línea 9'), contains('no está vinculado'));
    expect(problemAt('RMs línea 10'), contains('no está en Atletas'));
    expect(problemAt('RMs línea 11'), contains('"inventado" no está en el catálogo'));
    expect(problemAt('PesosAccesorios línea 6'), contains('"abc"'));
    expect(report.notes, contains(contains('RMs línea 7 (x1, peso_muerto): kilos en 0')));
    expect(report.problems.where((p) => p.contains('línea 7')), isEmpty, reason: '0 is "no data", not an error');
  });

  test('running it twice changes nothing', () async {
    await importer().run(run());
    final before = db.snapshot();
    final writes = db.writes;

    final second = await importer().run(run());
    expect(db.snapshot(), before);
    expect(db.writes, writes);
    expect(second.created, isEmpty);
    expect(second.unchanged, hasLength(4 + 3));
    expect(second.differing, isEmpty);
  });

  test('what the app already has is never overwritten: a different value is reported', () async {
    db.references.add(
      Reference(
        id: 'hand',
        clubId: _club,
        athleteId: 'ath-m',
        exerciseId: 'sq_espalda',
        type: ReferenceType.rm,
        value: 72,
        date: DateTime.utc(2026, 3, 1),
        origin: ReferenceOrigin.testeado,
        auditoria: _audit,
      ),
    );
    db.weights.add(
      FixedWeight(id: 'w', clubId: _club, athleteId: 'ath-m', exerciseId: 'curl_x', kg: 20, auditoria: _audit),
    );

    final report = await importer().run(run());
    expect(rm('ath-m', 'sq_espalda', DateTime.utc(2026, 3, 1)).value, 72);
    expect(db.weights.firstWhere((w) => w.id == 'w').kg, 20);
    expect(report.differing, hasLength(2));
    expect(report.differing.first, contains('en la app: 72 kg testeado'));
  });

  test('without the test dates every RM is importado', () async {
    await importer().run(
      run(
        adjustments: const {
          'athletes': {
            'sameAs': {'x1': 'Marti'},
          },
        },
      ),
    );
    expect(db.references.map((r) => r.origin).toSet(), {ReferenceOrigin.importado});
  });

  test('a dry run writes nothing and reports what it would create', () async {
    final report = await importer().run(run(dryRun: true));
    expect(db.writes, 0);
    expect(report.created, hasLength(4 + 3));
  });

  test('a row the use case refuses moves from created to problems', () async {
    db.exercises.remove('remo_x');
    final report = await importer().run(run());
    expect(
      report.problems,
      contains(contains('kilaje Marti · remo_x: 12 kg (PesosAccesorios línea 3): no se pudo escribir')),
    );
    expect(report.created, hasLength(4 + 2));
  });
}
