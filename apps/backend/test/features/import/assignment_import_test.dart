import 'package:maktub_backend/features/asignaciones/crear/crear_store.dart';
import 'package:maktub_backend/features/import/adjustments.dart';
import 'package:maktub_backend/features/import/assignments/assignment_import.dart';
import 'package:maktub_backend/features/import/assignments/assignment_import_store.dart';
import 'package:maktub_backend/features/import/import_run.dart';
import 'package:maktub_backend/features/import/sheets.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

const _club = 'club1';
final _audit = Auditoria.nueva('coach', ahora: DateTime.utc(2026, 9, 1));

/// The club in memory, seen through the import's reads and E6's create store.
class _Db implements AssignmentImportStore, CreateAssignmentStore {
  final groups_ = [
    AthleteGroup(id: 'g1', clubId: _club, name: 'Andi y Ari', memberIds: const ['ari', 'andi'], auditoria: _audit),
  ];

  /// Plan id → published?
  final plans = <String, bool>{};
  final all = <Assignment>[];

  @override
  Future<List<AthleteGroup>> groups(String clubId) async => groups_.where((g) => g.clubId == clubId).toList();

  @override
  Future<Set<String>> planIds(String clubId, Set<String> ids) async => ids.where(plans.containsKey).toSet();

  @override
  Future<Set<String>> publishedPlanIds(String clubId, Set<String> ids) async =>
      ids.where((id) => plans[id] == true).toSet();

  @override
  Future<Map<String, Assignment>> assignments(String clubId, Set<String> ids) async => {
    for (final a in all)
      if (a.clubId == clubId && ids.contains(a.id)) a.id: a,
  };

  @override
  Future<bool?> planIsPublished(String clubId, String planId) async => plans[planId];

  @override
  Future<bool> groupExists(String clubId, String groupId) async => groups_.any((g) => g.id == groupId);

  @override
  Future<bool> insert(Assignment assignment) async {
    if (all.any((a) => a.id == assignment.id)) throw StateError('duplicate _id');
    final taken = all.any(
      (a) =>
          a.groupId == assignment.groupId &&
          a.status == AssignmentStatus.active &&
          assignment.status == AssignmentStatus.active,
    );
    if (taken) return false;
    all.add(assignment);
    return true;
  }
}

void main() {
  late _Db db;

  setUp(() {
    db = _Db()
      ..plans[importedId(_club, 'plan_oct')] = true
      ..plans[importedId(_club, 'plan_borrador')] = false
      // The group runs another plan today: D14 must not stop the history.
      ..all.add(
        Assignment(
          id: 'now',
          clubId: _club,
          planId: 'nov',
          groupId: 'g1',
          startDate: DateTime.utc(2026, 11, 8),
          auditoria: _audit,
        ),
      );
  });

  ImportRun run(List<Map<String, Object?>> entries, {bool dryRun = false}) => ImportRun(
    club: importClubContext(_club, TipoClub.club),
    sheets: SheetDirectory('.'),
    adjustments: ImportAdjustments.fromJson({
      'plans': {'assignments': entries},
    }),
    dryRun: dryRun,
  );
  AssignmentImport importer() => AssignmentImport(reads: db, writes: db, now: () => DateTime.utc(2026, 11, 15));

  const oct = {'plan': 'plan_oct', 'group': 'andi y ari', 'from': '2026-10-01', 'to': '2026-11-05'};

  test('an entry becomes an ended assignment of the group, next to its active one', () async {
    final report = await importer().run(run([oct]));
    final a = db.all.singleWhere((a) => a.planId == importedId(_club, 'plan_oct'));
    expect(a.id, importedId(_club, 'asignacion-plan_oct-2026-10-01'));
    expect(a.groupId, 'g1');
    expect(
      (a.startDate, a.endDate, a.status),
      (DateTime.utc(2026, 10, 1), DateTime.utc(2026, 11, 5), AssignmentStatus.ended),
    );
    expect(a.auditoria.creadoPor, importAuthor);
    expect(report.created.single, contains('terminada'));
  });

  test('running twice creates nothing new; one changed in the app is left alone', () async {
    await importer().run(run([oct]));
    final again = await importer().run(run([oct]));
    expect(db.all, hasLength(2));
    expect(again.created, isEmpty);
    expect(again.unchanged, hasLength(1));

    final changed = await importer().run(
      run([
        {...oct, 'to': '2026-11-06'},
      ]),
    );
    expect(changed.differing.single, contains('no coincide'));
    expect(db.all.singleWhere((a) => a.id != 'now').endDate, DateTime.utc(2026, 11, 5));
  });

  test('a plan of one athlete, a draft, an unknown group or plan are reported and not written', () async {
    final report = await importer().run(
      run([
        {'plan': 'plan_oct', 'athlete': 'Ari', 'from': '2026-11-06', 'to': '2026-11-07'},
        {...oct, 'plan': 'plan_borrador'},
        {...oct, 'group': 'Otro'},
        {...oct, 'plan': 'plan_nada'},
      ]),
    );
    expect(db.all, hasLength(1));
    expect(report.problems, [
      allOf(contains('un solo atleta (Ari)'), contains('E6 solo asigna planes a grupos')),
      contains('borrador'),
      contains('no hay un grupo "Otro"'),
      contains('no está importado'),
    ]);
  });

  test('a dry run writes nothing', () async {
    final report = await importer().run(run([oct], dryRun: true));
    expect(db.all, hasLength(1));
    expect(report.created, hasLength(1));
  });
}
