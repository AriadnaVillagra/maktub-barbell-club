import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/sesion/data/shared_preferences_draft_store.dart';
import 'package:maktub_frontend/features/sesion/domain/session_draft_store.dart';
import 'package:maktub_frontend/features/sesion/domain/set_sync_queue.dart';
import 'package:maktub_frontend/features/sesion/domain/set_write.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'draft_fakes.dart';

/// The backend's per-set upsert (E7.3): one record per athlete and set, whoever writes it.
class _FakeServer {
  final records = <String, SetRecord>{};
  final received = <PendingSetWrite>[];
  bool offline = false;

  /// The server stores the write but the answer never arrives.
  bool loseAnswers = false;
  String? refuseWith;

  Future<SetRecord> send(PendingSetWrite p) async {
    if (offline) throw const ErrorDeApi('No se pudo conectar.');
    if (refuseWith case final message?) throw ErrorDeApi(message, estado: 422);
    received.add(p);
    final w = p.write;
    final key =
        '${p.sessionId}/${w.athleteId}/${w.blockIndex}/${w.prescriptionIndex}/${w.setIndex}';
    final record = records[key] = SetRecord(
      id: key,
      clubId: p.clubId,
      sessionId: p.sessionId,
      athleteId: w.athleteId,
      exerciseId: 'sq',
      exerciseName: 'Sentadilla',
      blockIndex: w.blockIndex,
      prescriptionIndex: w.prescriptionIndex,
      setIndex: w.setIndex,
      done: w.done,
      kg: w.manualKg ?? 80,
      reps: w.reps ?? 5,
      manualKg: w.manualKg != null,
      writtenBy: 'u',
      auditoria: Auditoria.nueva('u', ahora: DateTime.utc(2026, 11, 14)),
    );
    if (loseAnswers) throw const ErrorDeApi('No se pudo conectar.');
    return record;
  }
}

SetWrite _mark(String athlete, int set) => SetWrite.of(
  null,
  athleteId: athlete,
  blockIndex: 0,
  prescriptionIndex: 0,
  setIndex: set,
  adjustment: 0,
).toggled();

SetSyncQueue _queue(
  _FakeServer server,
  SessionDraftStore store, {
  Duration sendTimeout = const Duration(seconds: 10),
}) => SetSyncQueue(
  send: server.send,
  store: store,
  isRetryable: isTransientWriteError,
  sendTimeout: sendTimeout,
);

Future<SetRecord?> _submit(
  SetSyncQueue q,
  SetWrite w, {
  String session = 's1',
}) => q.submit(clubId: 'c1', sessionId: session, write: w);

void main() {
  test('without signal a mark stays in the draft and the queue', () async {
    final server = _FakeServer()..offline = true;
    final store = MemoryDraftStore();
    final queue = _queue(server, store);

    expect(await _submit(queue, _mark('ari', 0)), isNull);

    expect(queue.pending.single.write.done, isTrue);
    final saved = await store.load();
    expect(saved.queue.single.write.setIndex, 0);
    expect(saved.draft.single.write.done, isTrue);
    expect(server.records, isEmpty);
  });

  test('a new storage instance keeps the mark (a reload)', () async {
    final server = _FakeServer()..offline = true;
    final disk = DraftDisk();
    await _submit(_queue(server, MemoryDraftStore(disk)), _mark('ari', 1));

    final reloaded = _queue(server, MemoryDraftStore(disk));
    await reloaded.ready;

    expect(reloaded.pending.single.write.setIndex, 1);
    final unsent = await reloaded.resume('s1');
    expect(unsent.single.setIndex, 1);
    expect(unsent.single.done, isTrue);
  });

  test('when signal comes back the queue goes in order', () async {
    final server = _FakeServer()..offline = true;
    final queue = _queue(server, MemoryDraftStore());
    final changes = <int>[];
    queue.changes.listen((p) => changes.add(p.length));
    await _submit(queue, _mark('ari', 2));
    await _submit(queue, _mark('ari', 0));
    await _submit(queue, _mark('ari', 1).toggled());

    server.offline = false;
    final outcome = await queue.flush();

    expect(server.received.map((p) => p.write.setIndex), [2, 0, 1]);
    expect(server.received.map((p) => p.write.done), [true, true, false]);
    expect(outcome.stored, hasLength(3));
    expect(queue.pending, isEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(changes.last, 0);
  });

  test('a new write waits behind what is already queued', () async {
    final server = _FakeServer()..offline = true;
    final queue = _queue(server, MemoryDraftStore());
    await _submit(queue, _mark('ari', 0));

    server.offline = false;
    final stored = await _submit(queue, _mark('ari', 1));

    expect(stored?.setIndex, 1);
    expect(server.received.map((p) => p.write.setIndex), [0, 1]);
  });

  test(
    'resending something the server already took does not duplicate',
    () async {
      final server = _FakeServer()..loseAnswers = true;
      final queue = _queue(server, MemoryDraftStore());

      expect(await _submit(queue, _mark('ari', 0)), isNull);
      expect(queue.pending, hasLength(1));

      server.loseAnswers = false;
      await queue.flush();
      await _submit(queue, _mark('ari', 0));

      expect(server.received, hasLength(3));
      expect(server.records, hasLength(1));
      expect(server.records.values.single.done, isTrue);
      expect(queue.pending, isEmpty);
    },
  );

  test(
    'two devices writing different sets do not clobber each other',
    () async {
      final server = _FakeServer()..offline = true;
      final andi = _queue(server, MemoryDraftStore());
      final ari = _queue(server, MemoryDraftStore());
      await _submit(andi, _mark('andi', 0));
      await _submit(ari, _mark('ari', 0));
      await _submit(ari, _mark('ari', 1));
      await _submit(andi, _mark('andi', 1).edited(manualKg: 60, reps: 3));

      server.offline = false;
      await Future.wait([ari.flush(), andi.flush()]);

      expect(
        server.records.keys,
        unorderedEquals([
          's1/andi/0/0/0',
          's1/andi/0/0/1',
          's1/ari/0/0/0',
          's1/ari/0/0/1',
        ]),
      );
      expect(server.records['s1/ari/0/0/1']!.done, isTrue);
      expect(server.records['s1/andi/0/0/1']!.kg, 60);
      expect(andi.pending, isEmpty);
      expect(ari.pending, isEmpty);
    },
  );

  test('without local storage marking still works', () async {
    final server = _FakeServer();
    final queue = _queue(server, UnavailableDraftStore());

    expect((await _submit(queue, _mark('ari', 0)))?.done, isTrue);

    server.offline = true;
    expect(await _submit(queue, _mark('ari', 1)), isNull);
    expect(queue.pending, hasLength(1));
    expect(await queue.resume('s1'), hasLength(1));

    server.offline = false;
    await queue.flush();
    expect(server.records, hasLength(2));
  });

  test(
    'a refused write is thrown and leaves the queue and the draft',
    () async {
      final server = _FakeServer()..refuseWith = 'Ese atleta no está.';
      final store = MemoryDraftStore();
      final queue = _queue(server, store);

      await expectLater(
        _submit(queue, _mark('ari', 0)),
        throwsA(isA<ErrorDeApi>()),
      );

      expect(queue.pending, isEmpty);
      final saved = await store.load();
      expect(saved.queue, isEmpty);
      expect(saved.draft, isEmpty);
    },
  );

  test('a write that takes too long stays queued', () async {
    final hanging = Completer<SetRecord>();
    final queue = SetSyncQueue(
      send: (_) => hanging.future,
      store: MemoryDraftStore(),
      isRetryable: isTransientWriteError,
      sendTimeout: const Duration(milliseconds: 10),
    );

    expect(await _submit(queue, _mark('ari', 0)), isNull);
    expect(queue.pending, hasLength(1));
  });

  test(
    'opening a session forgets the draft of others with nothing to send',
    () async {
      final server = _FakeServer();
      final store = MemoryDraftStore();
      final queue = _queue(server, store);
      await _submit(queue, _mark('ari', 0), session: 'old');

      await queue.resume('s1');

      expect((await store.load()).draft, isEmpty);
    },
  );

  group('SharedPreferencesDraftStore', () {
    test('keeps the draft and the queue', () async {
      SharedPreferences.setMockInitialValues({});
      final p = PendingSetWrite(
        id: '1',
        clubId: 'c1',
        sessionId: 's1',
        write: _mark('ari', 0).edited(manualKg: 72.5, reps: 3).withNote(''),
      );
      await SharedPreferencesDraftStore().save(
        DraftSnapshot(draft: [p], queue: [p]),
      );

      final loaded = await SharedPreferencesDraftStore().load();

      expect(loaded.queue.single.write.toJson(), p.write.toJson());
      expect(loaded.draft.single.key, p.key);
    });

    test('unreadable data is an empty draft', () async {
      SharedPreferences.setMockInitialValues({
        SharedPreferencesDraftStore.key: 'not json',
      });

      final loaded = await SharedPreferencesDraftStore().load();

      expect(loaded.queue, isEmpty);
    });

    test('without storage it loads empty and saving does nothing', () async {
      final store = SharedPreferencesDraftStore(
        preferences: () => Future.error(StateError('blocked')),
      );

      expect((await store.load()).queue, isEmpty);
      await store.save(const DraftSnapshot());
    });
  });

  test('only a missing connection or a server failure is retried', () {
    expect(isTransientWriteError(const ErrorDeApi('sin red')), isTrue);
    expect(isTransientWriteError(const ErrorDeApi('x', estado: 503)), isTrue);
    expect(isTransientWriteError(const ErrorDeApi('x', estado: 401)), isTrue);
    expect(isTransientWriteError(const ErrorDeApi('x', estado: 422)), isFalse);
    expect(isTransientWriteError(StateError('bug')), isFalse);
  });
}
