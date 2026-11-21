import 'dart:io';

import 'package:maktub_backend/features/sesion/day_status/day_status_store.dart';
import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:test/test.dart';

/// Needs a local MongoDB; uses its own throwaway database and skips itself if none is reachable.
void main() {
  Db? db;
  const name = 'maktub_test_e7_13';

  setUpAll(() async {
    try {
      final base =
          Platform.environment['TEST_MONGO_URL'] ?? 'mongodb://localhost:27017';
      db = await abrirMongo('$base/$name');
    } on Object catch (e) {
      stderr.writeln('mongo: $e');
      db = null;
    }
  });

  tearDownAll(() async {
    await db?.drop();
    await db?.close();
  });

  var n = 0;
  Future<void> seed(
    String clubId,
    int day, {
    required bool recorded,
    bool done = true,
    int cycle = 1,
    String athleteId = 'ari',
    List<int> sets = const [0],
    int date = 0,
  }) async {
    final id = 'session-${n++}';
    final session = Session(
      id: id,
      clubId: clubId,
      assignmentId: 'a1',
      planId: 'p1',
      cycle: cycle,
      week: 1,
      day: day,
      date: DateTime.utc(2026, 11, 9 + day + date),
      auditoria: Auditoria.nueva('u1', ahora: DateTime.utc(2026, 11, 9)),
    );
    await db!
        .collection(Colecciones.sesiones)
        .insertOne(aDocumento(session.toJson()));
    if (!recorded) return;
    for (final set in sets) {
      final record = SetRecord(
        id: 'record-${n++}',
        clubId: clubId,
        sessionId: id,
        athleteId: athleteId,
        exerciseId: 'squat',
        exerciseName: 'Sentadilla',
        blockIndex: 0,
        prescriptionIndex: 0,
        setIndex: set,
        done: done,
        writtenBy: 'u1',
        auditoria: Auditoria.nueva('u1', ahora: DateTime.utc(2026, 11, 9)),
      );
      await db!
          .collection(Colecciones.registros)
          .insertOne(aDocumento(record.toJson()));
    }
  }

  test('only days with sets done count, and only of that club', () async {
    if (db == null) {
      markTestSkipped('MongoDB not available');
      return;
    }
    await db!.collection(Colecciones.sesiones).remove({});
    await db!.collection(Colecciones.registros).remove({});
    await seed('club-a', 1, recorded: true);
    await seed('club-a', 2, recorded: false);
    await seed('club-a', 3, recorded: true, done: false);
    await seed('club-a', 4, recorded: true, cycle: 2);
    await seed('club-b', 5, recorded: true);

    final store = MongoDayStatusStore(db!);
    final days = await store.doneDays('club-a', 'a1', [1]);

    expect([for (final d in days) d.day], [1]);
    expect(days.single.date, DateTime.utc(2026, 11, 10));
    expect(await store.doneDays('club-a', 'a1', [1, 2]), hasLength(2));
    expect(await store.doneDays('club-b', 'a1', [1]), hasLength(1));
    expect(await store.doneDays('club-c', 'a1', [1]), isEmpty);
  });

  test("an athlete's done sets, with their day and date, only of that club", () async {
    if (db == null) {
      markTestSkipped('MongoDB not available');
      return;
    }
    await db!.collection(Colecciones.sesiones).remove({});
    await db!.collection(Colecciones.registros).remove({});
    await seed('club-a', 1, recorded: true, sets: [0, 1]);
    await seed('club-a', 1, recorded: true, sets: [1, 2], date: 2);
    await seed('club-a', 2, recorded: true, athleteId: 'andi');
    await seed('club-a', 3, recorded: true, done: false);
    await seed('club-a', 4, recorded: true, cycle: 2);
    await seed('club-b', 5, recorded: true);

    final store = MongoDayStatusStore(db!);
    final sets = await store.doneSets('club-a', 'a1', [1], 'ari');

    expect(
      {for (final s in sets) (s.day, s.position.set, s.date.day)},
      {(1, 0, 10), (1, 1, 10), (1, 1, 12), (1, 2, 12)},
    );
    expect(sets.first.position.block, 0);
    expect(await store.doneSets('club-a', 'a1', [1], 'andi'), hasLength(1));
    expect(await store.doneSets('club-a', 'a1', [1, 2], 'ari'), hasLength(5));
    expect(await store.doneSets('club-b', 'a1', [1], 'ari'), hasLength(1));
    expect(await store.doneSets('club-c', 'a1', [1], 'ari'), isEmpty);
  });
}
