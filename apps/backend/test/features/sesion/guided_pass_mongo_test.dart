import 'dart:io';

import 'package:maktub_backend/features/acceso/club_context/club_context.dart';
import 'package:maktub_backend/features/sesion/live_broadcast.dart';
import 'package:maktub_backend/features/sesion/open_session/open_session_store.dart';
import 'package:maktub_backend/features/sesion/session_changes/session_changes_store.dart';
import 'package:maktub_backend/features/sesion/write_guided_pass/write_guided_pass.dart';
import 'package:maktub_backend/features/sesion/write_guided_pass/write_guided_pass_store.dart';
import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:test/test.dart';

/// Needs a local MongoDB; uses a throwaway database and skips itself if none is reachable.
void main() {
  Db? db;
  final name = 'maktub_test_e726_${DateTime.now().microsecondsSinceEpoch}';
  final t0 = DateTime.utc(2026, 11, 14, 10);

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

  void mongoTest(String description, Future<void> Function() body) {
    test(description, () async {
      if (db == null) {
        markTestSkipped('MongoDB not available');
        return;
      }
      await db!.collection(Colecciones.sesiones).remove({});
      await body();
    });
  }

  Session session({String clubId = 'club-a'}) => Session(
    id: 's1',
    clubId: clubId,
    assignmentId: 'a1',
    planId: 'p1',
    cycle: 1,
    week: 2,
    day: 1,
    date: DateTime.utc(2026, 11, 16),
    presentAthleteIds: const ['ari'],
    auditoria: Auditoria.nueva('u1', ahora: t0),
  );

  GuidedPassAction begin() => GuidedPassAction.begin(
    passId: 'p1',
    version: 0,
    at: t0,
    athleteIds: const ['ari', 'andi'],
    blocks: const [
      GuidedBlockStart(
        athleteMode: AthleteMode.turns,
        executionMode: ExecutionMode.circuit,
      ),
    ],
  );

  const coach = ClubContext(
    clubId: 'club-a',
    userId: 'coach',
    roles: {Rol.coach},
    clubType: TipoClub.club,
  );

  mongoTest('a session stored before the guided pass has none', () async {
    await MongoOpenSessionStore(db!).openOrResume(session());

    final read = await MongoWriteGuidedPassStore(db!).session('club-a', 's1');

    expect(read, isNotNull);
    expect(read!.guidedPass, isNull);
  });

  mongoTest(
    'the pass is stored as a change of the session, and the changes bring it',
    () async {
      final opened = await MongoOpenSessionStore(db!).openOrResume(session());
      final store = MongoWriteGuidedPassStore(db!);

      final stored = await store.setPass(
        'club-a',
        opened.id,
        applyGuidedAction(null, begin())!,
        sequence: await store.nextSequence('club-a', opened.id),
        userId: 'coach',
        at: t0,
      );

      expect(stored.guidedPass!.id, 'p1');
      expect(stored.guidedPass!.blocks.single.athleteMode, AthleteMode.turns);
      expect(stored.lastSessionChange, stored.sequence);
      expect(stored.auditoria.modificadoPor, 'coach');
      final changes = await MongoSessionChangesStore(db!)
          .session('club-a', opened.id);
      expect(changes!.guidedPass!.toJson(), stored.guidedPass!.toJson());
      expect(await store.session('club-b', opened.id), isNull);
    },
  );

  mongoTest('reopening the session adding athletes keeps the pass', () async {
    final open = MongoOpenSessionStore(db!);
    final opened = await open.openOrResume(session());
    final store = MongoWriteGuidedPassStore(db!);
    await store.setPass(
      'club-a',
      opened.id,
      applyGuidedAction(null, begin())!,
      sequence: await store.nextSequence('club-a', opened.id),
      userId: 'coach',
      at: t0,
    );

    final again = await open.openOrResume(
      Session.fromJson({
        ...session().toJson(),
        'id': 'other',
        'presentes': ['andi'],
      }),
    );

    expect(again.presentAthleteIds, containsAll(['ari', 'andi']));
    expect(again.guidedPass!.id, 'p1');
  });

  mongoTest('writes sent at once all land on the newest pass', () async {
    final opened = await MongoOpenSessionStore(db!).openOrResume(session());
    final write = WriteGuidedPass(
      MongoWriteGuidedPassStore(db!),
      MemoryLiveBroadcast(),
    );
    await write(coach, opened.id, begin().toJson());
    await write(
      coach,
      opened.id,
      GuidedPassAction.onBlock(
        GuidedActionKind.startBlock,
        passId: 'p1',
        version: 1,
        at: t0,
        block: 0,
      ).toJson(),
    );

    await Future.wait([
      for (final a in ['ari', 'andi'])
        write(
          coach,
          opened.id,
          GuidedPassAction.passSets(
            passId: 'p1',
            version: 2,
            at: t0,
            block: 0,
            sets: {AthleteSet(a, 0, 0)},
          ).toJson(),
        ),
    ]);
    await Future.wait([
      for (var i = 0; i < 2; i++)
        write(
          coach,
          opened.id,
          GuidedPassAction.onBlock(
            GuidedActionKind.finishBlock,
            passId: 'p1',
            version: 2,
            at: t0.add(Duration(minutes: 5 + i)),
            block: 0,
          ).toJson(),
        ),
    ]);

    final pass = (await MongoWriteGuidedPassStore(
      db!,
    ).session('club-a', opened.id))!.guidedPass!;
    expect(pass.blocks.single.passed, {
      const AthleteSet('ari', 0, 0),
      const AthleteSet('andi', 0, 0),
    });
    expect(pass.blocks.single.status, GuidedBlockStatus.done);
    expect(pass.blocks.single.end, isNotNull);
    expect(
      pass.blocks.single.end!.isBefore(t0.add(const Duration(minutes: 7))),
      true,
    );
    expect(pass.finished, true);
    expect(pass.version, 5);
  });
}
