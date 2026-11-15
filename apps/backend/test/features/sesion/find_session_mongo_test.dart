import 'dart:io';

import 'package:maktub_backend/features/sesion/find_session/find_session_store.dart';
import 'package:maktub_backend/features/sesion/open_session/open_session_store.dart';
import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:test/test.dart';

/// Needs a local MongoDB; uses a throwaway database and skips itself if none is reachable.
void main() {
  Db? db;
  final name = 'maktub_test_e727_${DateTime.now().microsecondsSinceEpoch}';

  setUpAll(() async {
    try {
      final base =
          Platform.environment['TEST_MONGO_URL'] ?? 'mongodb://localhost:27017';
      db = await abrirMongo('$base/$name');
      await asegurarIndices(db!);
    } on Object catch (e) {
      stderr.writeln('mongo: $e');
      db = null;
    }
  });

  tearDownAll(() async {
    await db?.drop();
    await db?.close();
  });

  Session candidate(String clubId) => Session(
    id: 'session-$clubId',
    clubId: clubId,
    assignmentId: 'a1',
    planId: 'p1',
    cycle: 1,
    week: 2,
    day: 1,
    date: DateTime.utc(2026, 11, 18),
    presentAthleteIds: const ['ari'],
    auditoria: Auditoria.nueva('u1', ahora: DateTime.utc(2026, 11, 18, 9)),
  );

  test('finds the session the opening stored, only in its club, and never '
      'writes', () async {
    if (db == null) {
      markTestSkipped('MongoDB not available');
      return;
    }
    final find = MongoFindSessionStore(db!);
    Future<Session?> lookup(String clubId, {int day = 1}) => find.session(
      clubId,
      assignmentId: 'a1',
      date: DateTime.utc(2026, 11, 18),
      week: 2,
      day: day,
    );

    expect(await lookup('club-a'), isNull);
    expect(await db!.collection(Colecciones.sesiones).count(), 0);

    final opened = await MongoOpenSessionStore(
      db!,
    ).openOrResume(candidate('club-a'));
    await db!.collection(Colecciones.registros).insertOne(
      aDocumento(
        SetRecord(
          id: 'r1',
          clubId: 'club-a',
          sessionId: opened.id,
          athleteId: 'ari',
          exerciseId: 'squat',
          exerciseName: 'Sentadilla',
          blockIndex: 0,
          prescriptionIndex: 0,
          setIndex: 0,
          done: true,
          writtenBy: 'u1',
          auditoria: Auditoria.nueva('u1', ahora: DateTime.utc(2026, 11, 18)),
        ).toJson(),
      ),
    );

    final found = await lookup('club-a');
    expect(found?.id, opened.id);
    expect(found?.presentAthleteIds, ['ari']);
    expect(await lookup('club-a', day: 2), isNull);
    expect(await lookup('club-b'), isNull);
    expect([for (final r in await find.records('club-a', opened.id)) r.id], [
      'r1',
    ]);
    expect(await find.records('club-b', opened.id), isEmpty);
    expect(await db!.collection(Colecciones.sesiones).count(), 1);
  });
}
