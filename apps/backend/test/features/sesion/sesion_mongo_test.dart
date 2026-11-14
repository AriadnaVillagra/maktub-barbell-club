import 'dart:convert';
import 'dart:io';

import 'package:maktub_backend/features/sesion/open_session/open_session_store.dart';
import 'package:maktub_backend/features/sesion/record_set/record_set_store.dart';
import 'package:maktub_backend/features/sesion/session_changes/session_changes_store.dart';
import 'package:maktub_backend/features/sesion/session_sequence.dart';
import 'package:maktub_backend/features/sesion/set_session_note/set_session_note_store.dart';
import 'package:maktub_backend/infraestructura/mongo.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:test/test.dart';

/// Needs a local MongoDB; uses a throwaway database and skips itself if none is reachable.
void main() {
  Db? db;
  final name = 'maktub_test_e73_${DateTime.now().microsecondsSinceEpoch}';

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
      await db!.collection(Colecciones.registros).remove({});
      await body();
    });
  }

  var n = 0;
  Session session({
    String clubId = 'club-a',
    int day = 1,
    List<String> present = const ['ari'],
    String createdBy = 'u1',
  }) => Session(
    id: 'session-${n++}',
    clubId: clubId,
    assignmentId: 'a1',
    planId: 'p1',
    cycle: 1,
    week: 2,
    day: day,
    date: DateTime.utc(2026, 11, 16),
    presentAthleteIds: present,
    auditoria: Auditoria.nueva(createdBy, ahora: DateTime.utc(2026, 11, 16, 9)),
  );

  SetRecord record({
    String clubId = 'club-a',
    String sessionId = 's1',
    String athleteId = 'ari',
    int setIndex = 0,
    double? kg = 80,
    int? reps = 5,
    double? workFactor,
    bool manualKg = false,
    String? note,
    String user = 'u1',
    DateTime? at,
  }) {
    final now = at ?? DateTime.utc(2026, 11, 16, 10);
    return SetRecord(
      id: 'record-${n++}',
      clubId: clubId,
      sessionId: sessionId,
      athleteId: athleteId,
      exerciseId: 'squat',
      exerciseName: 'Sentadilla',
      blockIndex: 0,
      prescriptionIndex: 0,
      setIndex: setIndex,
      target: const PlanSet(reps: 5, pct: 80),
      kg: kg,
      reps: reps,
      workFactor: workFactor,
      manualKg: manualKg,
      note: note,
      writtenBy: user,
      auditoria: Auditoria.nueva(user, ahora: now).modificada(user, ahora: now),
    );
  }

  Future<int> count(String collection) => db!.collection(collection).count();

  mongoTest('both unique indexes exist with the keys of the upserts', () async {
    await asegurarIndices(db!);
    final sessions = await db!.collection(Colecciones.sesiones).getIndexes();
    final sessionIndex = sessions.firstWhere(
      (i) => i['name'] == 'club_asignacion_fecha_semana_dia_unico',
    );
    expect(sessionIndex['unique'], isTrue);
    expect(sessionIndex['key'], {
      'clubId': 1,
      'asignacionId': 1,
      'fecha': 1,
      'semana': 1,
      'dia': 1,
    });

    final records = await db!.collection(Colecciones.registros).getIndexes();
    final recordIndex = records.firstWhere(
      (i) => i['name'] == 'club_sesion_atleta_posicion_unico',
    );
    expect(recordIndex['unique'], isTrue);
    expect(recordIndex['key'], {
      'clubId': 1,
      'sesionId': 1,
      'atletaId': 1,
      'bloque': 1,
      'prescripcion': 1,
      'serie': 1,
    });
  });

  group('open or resume', () {
    mongoTest('opening twice returns the same session, unchanged', () async {
      final store = MongoOpenSessionStore(db!);

      final first = await store.openOrResume(session());
      final second = await store.openOrResume(session(createdBy: 'u2'));

      expect(second.id, first.id);
      expect(second.auditoria.creadoPor, 'u1');
      expect(second.date, DateTime.utc(2026, 11, 16));
      expect(second.cycle, 1);
      expect(second.week, 2);
      expect(second.planId, 'p1');
      expect(await count(Colecciones.sesiones), 1);
    });

    mongoTest('a new open adds its athletes and removes none', () async {
      final store = MongoOpenSessionStore(db!);

      await store.openOrResume(session(present: ['ari']));
      final merged = await store.openOrResume(session(present: ['andi']));
      final again = await store.openOrResume(session(present: const []));

      expect(merged.presentAthleteIds, unorderedEquals(['ari', 'andi']));
      expect(again.presentAthleteIds, unorderedEquals(['ari', 'andi']));
    });

    mongoTest('other day and other club are other sessions', () async {
      final store = MongoOpenSessionStore(db!);

      final first = await store.openOrResume(session());
      final otherDay = await store.openOrResume(session(day: 2));
      final otherClub = await store.openOrResume(session(clubId: 'club-b'));

      expect({first.id, otherDay.id, otherClub.id}, hasLength(3));
      expect(await count(Colecciones.sesiones), 3);
    });

    mongoTest('concurrent opens end on one session with every athlete', () async {
      final store = MongoOpenSessionStore(db!);

      final opened = await Future.wait([
        for (var i = 0; i < 20; i++) store.openOrResume(session(present: ['a$i'])),
      ]);

      expect({for (final s in opened) s.id}, hasLength(1));
      expect(await count(Colecciones.sesiones), 1);
      final last = await store.openOrResume(session(present: const []));
      expect(last.presentAthleteIds, hasLength(20));
    });

    mongoTest('a duplicate key that retrying cannot solve fails loudly', () async {
      final sessions = db!.collection(Colecciones.sesiones);
      await sessions.insertOne(aDocumento(session().toJson(), id: 'taken'));

      expect(
        () => upsertByUniqueKey(
          sessions,
          {'clubId': 'club-z', 'asignacionId': 'a9', 'fecha': 'x', 'semana': 1, 'dia': 1},
          {
            r'$setOnInsert': {'_id': 'taken'},
          },
        ),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', contains('E11000')),
        ),
      );
    });

    mongoTest('records only come from that club and session', () async {
      final write = MongoRecordSetStore(db!);
      await write.upsert(record());
      await write.upsert(record(sessionId: 's2'));
      await write.upsert(record(clubId: 'club-b'));
      final store = MongoOpenSessionStore(db!);

      expect(await store.records('club-a', 's1'), hasLength(1));
      expect(await store.records('club-c', 's1'), isEmpty);
    });
  });

  group('session note', () {
    Future<void> insertSession() => db!.collection(Colecciones.sesiones).insertOne({
      '_id': 's1',
      'clubId': 'club-a',
      'asignacionId': 'a1',
      'planId': 'p1',
      'ciclo': 1,
      'semana': 1,
      'dia': 1,
      'fecha': '2026-11-16',
      'presentes': ['ari'],
      'auditoria': Auditoria.nueva('u1', ahora: DateTime.utc(2026, 11, 16, 9)).toJson(),
    });

    mongoTest('writes only the note and the modification audit, and clears it', () async {
      await insertSession();
      final store = MongoSetSessionNoteStore(db!);
      final at = DateTime.utc(2026, 11, 16, 10);

      final written = await store.setNote('club-a', 's1', 'Buen día', sequence: 3, userId: 'u2', at: at);
      final cleared = await store.setNote('club-a', 's1', null, sequence: 4, userId: 'u2', at: at);

      expect(written.note, 'Buen día');
      expect(written.presentAthleteIds, ['ari']);
      expect(written.auditoria.creadoPor, 'u1');
      expect(written.auditoria.modificadoPor, 'u2');
      expect(written.lastSessionChange, 3);
      expect(cleared.note, isNull);
      expect(cleared.lastSessionChange, 4);
    });

    mongoTest('the change counter goes up by one and stays per session', () async {
      await insertSession();

      expect(await nextSessionSequence(db!, 'club-a', 's1'), 1);
      expect(await nextSessionSequence(db!, 'club-a', 's1'), 2);
      expect(
        () => nextSessionSequence(db!, 'club-b', 's1'),
        throwsStateError,
      );
    });

    mongoTest('a change of who is present takes a number', () async {
      await insertSession();

      final changed = await MongoOpenSessionStore(db!).markChanged('club-a', 's1');

      expect(changed.sequence, 1);
      expect(changed.lastSessionChange, 1);
    });

    mongoTest('resync: only records above the number, of that club and session', () async {
      final write = MongoRecordSetStore(db!);
      final store = MongoSessionChangesStore(db!);
      SetRecord numbered(int set, int sequence, {String clubId = 'club-a', String sessionId = 's1'}) =>
          SetRecord.fromJson({
            ...record(setIndex: set, clubId: clubId, sessionId: sessionId).toJson(),
            'secuencia': sequence,
          });
      await write.upsert(numbered(0, 1));
      await write.upsert(numbered(1, 2));
      await write.upsert(numbered(2, 3));
      await write.upsert(numbered(3, 4, clubId: 'club-b'));
      await write.upsert(numbered(4, 5, sessionId: 's2'));
      await write.upsert(record(setIndex: 5));

      final found = await store.recordsAfter('club-a', 's1', 1);

      expect(found.map((r) => r.sequence).toSet(), {2, 3});
    });

    mongoTest('what comes back reads the same as what went in, so a repeat is detected', () async {
      final store = MongoRecordSetStore(db!);
      String content(SetRecord r) => jsonEncode(
        r.toJson()
          ..remove('id')
          ..remove('auditoria'),
      );
      final sent = record(kg: 80, workFactor: 90, note: 'Liviano');

      await store.upsert(sent);

      expect(content((await store.stored(sent))!), content(sent));
    });

    mongoTest('a record finds what is stored under its key', () async {
      final store = MongoRecordSetStore(db!);
      expect(await store.stored(record()), isNull);

      await store.upsert(record(note: 'Liviano'));

      expect((await store.stored(record()))!.note, 'Liviano');
      expect(await store.stored(record(setIndex: 1)), isNull);
    });
  });

  group('record a set', () {
    mongoTest('repeating a write keeps one record and its identity', () async {
      final store = MongoRecordSetStore(db!);

      final first = await store.upsert(record());
      final retry = await store.upsert(
        record(user: 'u2', at: DateTime.utc(2026, 11, 16, 11)),
      );

      expect(retry.id, first.id);
      expect(retry.auditoria.creadoPor, 'u1');
      expect(retry.auditoria.creadoEn, DateTime.utc(2026, 11, 16, 10));
      expect(retry.auditoria.modificadoPor, 'u2');
      expect(retry.auditoria.modificadoEn, DateTime.utc(2026, 11, 16, 11));
      expect(retry.writtenBy, 'u2');
      expect(await count(Colecciones.registros), 1);
    });

    mongoTest('keepNote leaves the stored note, otherwise it follows the record', () async {
      final store = MongoRecordSetStore(db!);

      await store.upsert(record(note: 'Liviano'));
      final kept = await store.upsert(record(kg: 85), keepNote: true);
      final cleared = await store.upsert(record(kg: 85));

      expect(kept.note, 'Liviano');
      expect(kept.kg, 85);
      expect(cleared.note, isNull);
      expect(await db!.collection(Colecciones.registros).findOne(), isNot(contains('nota')));
    });

    mongoTest('a rewrite replaces values and clears what it dropped', () async {
      final store = MongoRecordSetStore(db!);

      await store.upsert(record(workFactor: 80, manualKg: true));
      final rewritten = await store.upsert(record(kg: 85, reps: null));

      expect(rewritten.kg, 85);
      expect(rewritten.reps, isNull);
      expect(rewritten.workFactor, isNull);
      expect(rewritten.manualKg, isFalse);
      final raw = await db!.collection(Colecciones.registros).findOne();
      expect(raw, isNot(contains('reps')));
      expect(raw, isNot(contains('factor')));
      expect(raw, isNot(contains('kilosManual')));
    });

    mongoTest('different sets written at once do not touch each other', () async {
      final store = MongoRecordSetStore(db!);

      await Future.wait([
        for (var s = 0; s < 10; s++)
          for (final athlete in ['ari', 'andi'])
            store.upsert(record(athleteId: athlete, setIndex: s, kg: 60.0 + s)),
      ]);

      expect(await count(Colecciones.registros), 20);
      final docs = await db!.collection(Colecciones.registros).find().toList();
      for (final d in docs) {
        expect(d['kilos'], 60 + (d['serie'] as int));
      }
    });

    mongoTest('the same set written at once stays one record', () async {
      final store = MongoRecordSetStore(db!);

      final results = await Future.wait([
        for (var i = 0; i < 20; i++) store.upsert(record(kg: 60.0 + i)),
      ]);

      expect({for (final r in results) r.id}, hasLength(1));
      expect(await count(Colecciones.registros), 1);
    });

    mongoTest('sessions and references stay inside the club', () async {
      await db!.collection(Colecciones.sesiones).insertOne(
        aDocumento(session().toJson(), id: 's1'),
      );
      await db!.collection(Colecciones.equipos).remove({});
      await db!.collection(Colecciones.kilajesFijos).remove({});
      await db!.collection(Colecciones.kilajesFijos).insertOne({
        '_id': 'k1',
        'clubId': 'club-a',
        'atletaId': 'ari',
        'ejercicioId': 'squat',
        'kilos': 12.5,
        'auditoria': Auditoria.nueva('u', ahora: DateTime.utc(2026)).toJson(),
      });
      final store = MongoRecordSetStore(db!);

      expect((await store.session('club-a', 's1'))?.id, 's1');
      expect(await store.session('club-b', 's1'), isNull);
      expect((await store.fixedWeight('club-a', 'ari', 'squat'))?.kg, 12.5);
      expect(await store.fixedWeight('club-b', 'ari', 'squat'), isNull);
      expect(await store.equipment('club-a'), isNull);
    });
  });

  mongoTest('stored documents read back through the models', () async {
    final store = MongoRecordSetStore(db!);
    final doc = ObjectId().oid;

    final saved = await store.upsert(
      SetRecord(
        id: doc,
        clubId: 'club-a',
        sessionId: 's1',
        athleteId: 'ari',
        exerciseId: 'squat',
        exerciseName: 'Sentadilla',
        blockIndex: 1,
        prescriptionIndex: 2,
        setIndex: 3,
        target: const PlanSet(reps: 5, pct: 80),
        kg: 80,
        reps: 5,
        referenceId: 'r1',
        referenceValue: 100,
        workFactor: 90,
        pctPlan: 80,
        pctReal: 72,
        writtenBy: 'u1',
        auditoria: Auditoria.nueva(
          'u1',
          ahora: DateTime.utc(2026, 11, 16),
        ).modificada('u1', ahora: DateTime.utc(2026, 11, 16)),
      ),
    );

    expect(saved.id, doc);
    expect(saved.blockIndex, 1);
    expect(saved.setIndex, 3);
    expect(saved.target.pct, 80);
    expect(saved.pctReal, 72);
    expect(saved.referenceValue, 100);
  });
}
