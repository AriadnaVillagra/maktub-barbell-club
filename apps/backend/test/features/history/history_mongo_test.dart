import 'dart:io';

import 'package:maktub_backend/features/history/list_history/list_history_store.dart';
import 'package:maktub_backend/features/history/session_history/session_history_store.dart';
import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:test/test.dart';

import 'history_fakes.dart';

/// Needs a local MongoDB; uses its own throwaway database and skips itself if none is reachable.
void main() {
  Db? db;
  const name = 'maktub_test_history';

  setUpAll(() async {
    try {
      final base = Platform.environment['TEST_MONGO_URL'] ?? 'mongodb://localhost:27017';
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

  Future<void> insert(String collection, Json json) =>
      db!.collection(collection).insertOne(aDocumento(json));

  Future<void> reset() async {
    for (final c in [
      Colecciones.atletas,
      Colecciones.sesiones,
      Colecciones.registros,
      Colecciones.planes,
      Colecciones.tiemposBloque,
      Colecciones.ejercicios,
    ]) {
      await db!.collection(c).remove({});
    }
  }

  test('lists the athlete\'s sessions of the club by date, pages back, and reads plans and records', () async {
    if (db == null) {
      markTestSkipped('MongoDB not available');
      return;
    }
    await reset();
    await insert(Colecciones.atletas, {'id': 'ath-1', 'clubId': 'club-a', 'usuarioId': 'user-1'});
    for (final s in [
      session('s1', date: DateTime.utc(2026, 4, 1)),
      session('s2', date: DateTime.utc(2026, 4, 3)),
      session('s3', date: DateTime.utc(2026, 4, 3), planId: 'p2'),
      session('s4', date: DateTime.utc(2026, 5, 1), present: ['ath-2']),
      session('s5', date: DateTime.utc(2026, 6, 1), clubId: 'club-b'),
    ]) {
      await insert(Colecciones.sesiones, s.toJson());
    }
    await insert(Colecciones.planes, plan().toJson());
    await insert(Colecciones.planes, plan(id: 'p2', clubId: 'club-b').toJson());
    await insert(Colecciones.registros, record('s2', kg: 70, estimated: true).toJson());
    await insert(Colecciones.registros, record('s2', set: 1, done: false).toJson());
    await insert(Colecciones.registros, record('s2', athleteId: 'ath-2').toJson());
    await insert(Colecciones.registros, record('s2', clubId: 'club-b', set: 2).toJson());

    final store = MongoListHistoryStore(db!);
    expect(await store.athleteUserId('club-a', 'ath-1'), 'user-1');
    expect(await store.athleteUserId('club-b', 'ath-1'), isNull);

    final all = await store.sessionsBefore('club-a', 'ath-1', limit: 10);
    expect([for (final s in all) s.date], [DateTime.utc(2026, 4, 3), DateTime.utc(2026, 4, 3), DateTime.utc(2026, 4, 1)]);
    final page = await store.sessionsBefore('club-a', 'ath-1', limit: 1);
    expect(page.single.date, DateTime.utc(2026, 4, 3));
    final older = await store.sessionsBefore('club-a', 'ath-1', before: DateTime.utc(2026, 4, 3), limit: 10);
    expect([for (final s in older) s.id], ['s1']);
    expect(
      {for (final s in await store.sessionsOn('club-a', 'ath-1', DateTime.utc(2026, 4, 3))) s.id},
      {'s2', 's3'},
    );

    final plans = await store.plans('club-a', {'p1', 'p2', 'gone'});
    expect(plans.keys, ['p1']);
    expect(plans['p1']!.name, 'Abril 2026');

    final records = await store.records('club-a', 'ath-1', ['s2', 's1']);
    expect(
      {for (final r in records) (r.sessionId, r.mark.position.set, r.mark.done, r.mark.estimated)},
      {('s2', 0, true, true), ('s2', 1, false, false)},
    );
  });

  test('reads one session with the athlete\'s records, times and catalog names', () async {
    if (db == null) {
      markTestSkipped('MongoDB not available');
      return;
    }
    await reset();
    await insert(Colecciones.atletas, {'id': 'ath-1', 'clubId': 'club-a', 'usuarioId': 'user-1'});
    await insert(Colecciones.sesiones, session('s1', date: DateTime.utc(2026, 4, 1)).toJson());
    await insert(Colecciones.planes, plan().toJson());
    await insert(Colecciones.registros, record('s1', kg: 70).toJson());
    await insert(Colecciones.registros, record('s1', athleteId: 'ath-2').toJson());
    await insert(Colecciones.registros, record('s1', clubId: 'club-b', set: 1).toJson());
    for (final (id, clubId, athletes) in [
      ('t1', 'club-a', ['ath-1']),
      ('t2', 'club-a', ['ath-2']),
      ('t3', 'club-b', ['ath-1']),
    ]) {
      await insert(
        Colecciones.tiemposBloque,
        BlockTime(
          id: id,
          clubId: clubId,
          sessionId: 's1',
          blockIndex: 0,
          blockName: 'Principal',
          athleteIds: athletes,
          start: DateTime.utc(2026, 4, 1, 10),
          end: DateTime.utc(2026, 4, 1, 10, 5),
          auditoria: audit,
        ).toJson(),
      );
    }
    for (final (id, clubId, name) in [
      ('bench', clubPlataforma, 'Press de banca'),
      ('own', 'club-a', 'Propio'),
      ('foreign', 'club-b', 'Ajeno'),
    ]) {
      await insert(Colecciones.ejercicios, {'id': id, 'clubId': clubId, 'nombre': name});
    }

    final store = MongoSessionHistoryStore(db!);
    expect(await store.athleteUserId('club-a', 'ath-1'), 'user-1');
    expect((await store.session('club-a', 's1'))!.id, 's1');
    expect(await store.session('club-b', 's1'), isNull);
    expect((await store.plan('club-a', 'p1'))!.name, 'Abril 2026');
    expect(await store.plan('club-b', 'p1'), isNull);
    final records = await store.records('club-a', 's1', 'ath-1');
    expect(records.single.kg, 70);
    expect([for (final t in await store.blockTimes('club-a', 's1', 'ath-1')) t.id], ['t1']);
    expect(
      await store.exerciseNames('club-a', {'bench', 'own', 'foreign', 'missing'}),
      {'bench': 'Press de banca', 'own': 'Propio'},
    );
  });
}
