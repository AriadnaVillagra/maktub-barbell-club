import 'dart:io';

import 'package:maktub_backend/features/sesion/block_times/block_times_store.dart';
import 'package:maktub_backend/features/sesion/record_block_time/record_block_time_store.dart';
import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:test/test.dart';

/// Needs a local MongoDB; uses a throwaway database and skips itself if none is reachable.
void main() {
  Db? db;
  final name = 'maktub_test_e719_${DateTime.now().microsecondsSinceEpoch}';

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
      await db!.collection(Colecciones.tiemposBloque).remove({});
      await body();
    });
  }

  BlockTime time(
    String id, {
    String clubId = 'club-a',
    String user = 'u1',
    DateTime? at,
    AthleteMode? mode = AthleteMode.simultaneous,
    DateTime? start,
    int minutes = 10,
  }) {
    final now = at ?? DateTime.utc(2026, 11, 16, 19);
    final from = start ?? DateTime.utc(2026, 11, 16, 18);
    return BlockTime(
      id: id,
      clubId: clubId,
      sessionId: 's1',
      blockIndex: 1,
      blockName: 'Fuerza',
      athleteMode: mode,
      athleteIds: const ['ari'],
      start: from,
      end: from.add(Duration(minutes: minutes)),
      auditoria: Auditoria.nueva(user, ahora: now).modificada(user, ahora: now),
    );
  }

  mongoTest('the club and session index exists', () async {
    final indexes = await db!
        .collection(Colecciones.tiemposBloque)
        .getIndexes();
    final index = indexes.firstWhere((i) => i['name'] == 'club_sesion');
    expect(index['key'], {'clubId': 1, 'sesionId': 1});
  });

  mongoTest('writing the same id twice leaves one document', () async {
    final store = MongoRecordBlockTimeStore(db!);

    await store.upsert(time('t1'));
    final second = await store.upsert(
      time('t1', user: 'u2', at: DateTime.utc(2026, 11, 16, 20), minutes: 12),
    );

    expect(await db!.collection(Colecciones.tiemposBloque).count(), 1);
    expect(second.seconds, 720);
    expect(second.auditoria.creadoPor, 'u1');
    expect(second.auditoria.modificadoPor, 'u2');
  });

  mongoTest('a rewrite without athlete mode clears it', () async {
    final store = MongoRecordBlockTimeStore(db!);

    await store.upsert(time('t1'));
    final second = await store.upsert(time('t1', mode: null));

    expect(second.athleteMode, isNull);
  });

  mongoTest(
    'two ids for the same block leave two times, read in order',
    () async {
      final write = MongoRecordBlockTimeStore(db!);
      await write.upsert(time('late', start: DateTime.utc(2026, 11, 16, 19)));
      await write.upsert(time('early'));
      await write.upsert(time('other-club', clubId: 'club-b'));

      final times = await MongoBlockTimesStore(db!).timesOf('club-a', 's1');

      expect(times.map((t) => t.id), ['early', 'late']);
      expect(await MongoBlockTimesStore(db!).timesOf('club-b', 's2'), isEmpty);
    },
  );
}
