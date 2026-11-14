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
      date: DateTime.utc(2026, 11, 9 + day),
      auditoria: Auditoria.nueva('u1', ahora: DateTime.utc(2026, 11, 9)),
    );
    await db!
        .collection(Colecciones.sesiones)
        .insertOne(aDocumento(session.toJson()));
    if (!recorded) return;
    final record = SetRecord(
      id: 'record-${n++}',
      clubId: clubId,
      sessionId: id,
      athleteId: 'ari',
      exerciseId: 'squat',
      exerciseName: 'Sentadilla',
      blockIndex: 0,
      prescriptionIndex: 0,
      setIndex: 0,
      done: done,
      writtenBy: 'u1',
      auditoria: Auditoria.nueva('u1', ahora: DateTime.utc(2026, 11, 9)),
    );
    await db!
        .collection(Colecciones.registros)
        .insertOne(aDocumento(record.toJson()));
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
}
