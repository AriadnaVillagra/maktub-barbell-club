import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/core/offline/local_copy.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/sesion/data/shared_preferences_draft_store.dart';
import 'package:maktub_frontend/features/sesion/domain/athlete_adjustments.dart';
import 'package:maktub_frontend/features/sesion/domain/block_time_write.dart';
import 'package:maktub_frontend/features/sesion/domain/live_session_sync.dart';
import 'package:maktub_frontend/features/sesion/domain/open_day_session.dart';
import 'package:maktub_frontend/features/sesion/domain/session_draft_store.dart';
import 'package:maktub_frontend/features/sesion/domain/session_repository.dart';
import 'package:maktub_frontend/features/sesion/domain/set_sync_queue.dart';
import 'package:maktub_frontend/features/sesion/domain/set_write.dart';

import 'draft_fakes.dart';

final _date = DateTime.utc(2026, 11, 14);

/// The backend of E7.3 and E7.19: opening is an upsert by assignment, date, week and day that adds who is present;
/// a set is an upsert by session, athlete and position; a time, by its id. It refuses writes to a session it does
/// not have, as the real one answers 404.
class _IdempotentServer {
  final sessions = <String, Session>{};
  final records = <String, SetRecord>{};
  final times = <String, (String, BlockTimeWrite)>{};

  /// Every request taken, in order: `open <id>`, `set <session> <athlete> <set>`, `time <session> <id>`.
  final log = <String>[];
  var _ids = 0;
  String? refuseOpening;

  LiveSession open(
    String clubId,
    String assignmentId,
    DateTime date,
    int week,
    int day,
    Set<String> present,
  ) {
    if (refuseOpening case final message?) {
      throw ErrorDeApi(message, estado: 409);
    }
    final key = '$clubId/$assignmentId/${aIsoFecha(date)}/$week/$day';
    final before = sessions[key];
    final session = sessions[key] = Session(
      id: before?.id ?? 'srv-${++_ids}',
      clubId: clubId,
      assignmentId: assignmentId,
      planId: 'p1',
      cycle: 1,
      week: week,
      day: day,
      date: date,
      presentAthleteIds: {...?before?.presentAthleteIds, ...present}.toList(),
      auditoria: Auditoria.nueva('server', ahora: _date),
    );
    log.add('open ${session.id}');
    return LiveSession(
      session: session,
      records: [
        for (final r in records.values)
          if (r.sessionId == session.id) r,
      ],
    );
  }

  void _known(String sessionId) {
    if (!sessions.values.any((s) => s.id == sessionId)) {
      throw const ErrorDeApi('Sesión no encontrada.', estado: 404);
    }
  }

  SetRecord recordSet(String clubId, String sessionId, SetWrite w) {
    _known(sessionId);
    log.add('set $sessionId ${w.athleteId} ${w.setIndex}');
    final key =
        '$sessionId/${w.athleteId}/${w.blockIndex}/${w.prescriptionIndex}/${w.setIndex}';
    return records[key] = SetRecord(
      id: key,
      clubId: clubId,
      sessionId: sessionId,
      athleteId: w.athleteId,
      exerciseId: 'sq',
      exerciseName: 'Sentadilla',
      blockIndex: w.blockIndex,
      prescriptionIndex: w.prescriptionIndex,
      setIndex: w.setIndex,
      done: w.done,
      kg: 80,
      reps: 5,
      writtenBy: 'u',
      auditoria: Auditoria.nueva('u', ahora: _date),
    );
  }

  void recordBlockTime(String sessionId, String timeId, BlockTimeWrite w) {
    _known(sessionId);
    log.add('time $sessionId $timeId');
    times[timeId] = (sessionId, w);
  }

  Iterable<SetRecord> recordsOf(String sessionId) =>
      records.values.where((r) => r.sessionId == sessionId);
}

/// One phone: its signal, its storage and what it saw of each session, over the shared server.
class _Phone implements SessionRepository, SessionCopy {
  _Phone(this.server, [DraftDisk? disk]) : disk = disk ?? DraftDisk();

  final _IdempotentServer server;
  final DraftDisk disk;
  var online = false;

  /// The session copy, by the server's key of the day (E7.15).
  final copies = <String, LiveSession>{};

  late SetSyncQueue queue = _newQueue();

  SetSyncQueue _newQueue() => SetSyncQueue(
    send: (p) => recordSet(p.clubId, p.sessionId, p.write),
    sendTime: (t) => recordBlockTime(t.clubId, t.sessionId, t.id, t.write),
    sendOpen: (o) => openOnServer(
      o.clubId,
      assignmentId: o.assignmentId,
      date: o.date,
      week: o.week,
      day: o.day,
      presentAthleteIds: o.presentAthleteIds.toSet(),
    ),
    store: MemoryDraftStore(disk),
    isRetryable: isTransientWriteError,
  );

  /// The app starting again: the queue reads back what the storage kept.
  void reload() => queue = _newQueue();

  OpenDaySession get opener => OpenDaySession(
    sessions: this,
    queue: queue,
    copy: this,
    userId: 'u',
    newLocalId: () => '${identityHashCode(this)}',
  );

  void _check() {
    if (!online) throw const ErrorDeApi('No se pudo conectar con el servidor.');
  }

  static String _dayKey(Session s) =>
      '${s.assignmentId}/${aIsoFecha(s.date)}/${s.week}/${s.day}';

  @override
  Future<LiveSession> open(
    String clubId, {
    required String assignmentId,
    required DateTime date,
    required int week,
    required int day,
    required Set<String> presentAthleteIds,
  }) async {
    try {
      return await openOnServer(
        clubId,
        assignmentId: assignmentId,
        date: date,
        week: week,
        day: day,
        presentAthleteIds: presentAthleteIds,
      );
    } catch (e) {
      if (!isOfflineError(e)) rethrow;
      final copy = copies['$assignmentId/${aIsoFecha(date)}/$week/$day'];
      if (copy == null) throw const SessionNotOpenedHere();
      return copy;
    }
  }

  @override
  Future<LiveSession> openOnServer(
    String clubId, {
    required String assignmentId,
    required DateTime date,
    required int week,
    required int day,
    required Set<String> presentAthleteIds,
  }) async {
    _check();
    final live = server.open(
      clubId,
      assignmentId,
      date,
      week,
      day,
      presentAthleteIds,
    );
    await remember(live);
    return live;
  }

  @override
  Future<void> remember(LiveSession live) async =>
      copies[_dayKey(live.session)] = live;

  @override
  Future<void> applyChanges(
    String clubId,
    String sessionId,
    List<SessionChange> changes,
  ) async {}

  @override
  Future<SetRecord> recordSet(
    String clubId,
    String sessionId,
    SetWrite write,
  ) async {
    _check();
    return server.recordSet(clubId, sessionId, write);
  }

  @override
  Future<void> recordBlockTime(
    String clubId,
    String sessionId,
    String timeId,
    BlockTimeWrite write,
  ) async {
    _check();
    server.recordBlockTime(sessionId, timeId, write);
  }

  @override
  Future<List<ProposedSet>> proposedLoads(
    String clubId,
    String sessionId,
    String athleteId,
    AthleteAdjustments adjustments,
  ) => throw UnimplementedError();

  @override
  Future<LiveSession?> find(
    String clubId, {
    required String assignmentId,
    required DateTime date,
    required int week,
    required int day,
  }) => throw UnimplementedError();

  @override
  Future<Session> writeGuidedPass(
    String clubId,
    String sessionId,
    GuidedPassAction action,
  ) => throw UnimplementedError();

  @override
  Future<Session> saveSessionNote(
    String clubId,
    String sessionId,
    String note,
  ) => throw UnimplementedError();
}

final _day = DayToOpen(
  clubId: 'c1',
  assignmentId: 'a1',
  planId: 'p1',
  cycle: 1,
  date: _date,
  week: 2,
  day: 1,
);

SetWrite _mark(String athlete, int set) => SetWrite.of(
  null,
  athleteId: athlete,
  blockIndex: 0,
  prescriptionIndex: 0,
  setIndex: set,
  adjustment: 0,
).toggled();

BlockTimeWrite _time(int block) => BlockTimeWrite(
  blockIndex: block,
  blockName: 'Principal',
  athleteIds: const ['ari'],
  start: _date,
  end: _date.add(const Duration(minutes: 10)),
);

Future<void> _markOn(_Phone phone, LiveSession live, String athlete, int set) =>
    phone.queue.submit(
      clubId: 'c1',
      sessionId: live.session.id,
      write: _mark(athlete, set),
    );

void main() {
  test('without signal and without a session on the server, the day opens on the phone and sets are marked', () async {
    final server = _IdempotentServer();
    final phone = _Phone(server);

    final live = await phone.opener(_day, {'ari'});
    await _markOn(phone, live, 'ari', 0);
    await _markOn(phone, live, 'ari', 1);

    expect(isLocalSessionId(live.session.id), isTrue);
    expect(live.session.presentAthleteIds, ['ari']);
    expect(
      (live.session.week, live.session.day, live.session.date),
      (2, 1, _date),
    );
    expect(live.records, isEmpty);
    expect(phone.copies.values.single.session.id, live.session.id);
    expect(phone.queue.pendingOpens.single.sessionId, live.session.id);
    expect(phone.queue.pending.map((p) => p.sessionId), [
      live.session.id,
      live.session.id,
    ]);
    expect(server.log, isEmpty);
  });

  test('reloading without signal keeps the session opened on the phone and its marks', () async {
    final server = _IdempotentServer();
    final phone = _Phone(server);
    final live = await phone.opener(_day, {'ari'});
    await _markOn(phone, live, 'ari', 0);

    phone.reload();
    final again = await phone.opener(_day, {'ari'});

    expect(again.session.id, live.session.id);
    expect(phone.queue.pendingOpens, hasLength(1));
    final unsent = await phone.queue.resume(again.session.id);
    expect(unsent.single.setIndex, 0);
    expect(unsent.single.done, isTrue);
  });

  test('when signal returns the opening goes first, then the sets and times, in order, with the server id', () async {
    final server = _IdempotentServer();
    final phone = _Phone(server);
    final live = await phone.opener(_day, {'ari'});
    await _markOn(phone, live, 'ari', 1);
    await phone.queue.submitBlockTime(
      clubId: 'c1',
      sessionId: live.session.id,
      write: _time(0),
    );
    await _markOn(phone, live, 'ari', 0);
    final opened = <SessionOpened>[];
    phone.queue.opened.listen(opened.add);

    phone.online = true;
    final outcome = await phone.queue.flush();

    final timeId = server.times.keys.single;
    expect(server.log, [
      'open srv-1',
      'set srv-1 ari 1',
      'set srv-1 ari 0',
      'time srv-1 $timeId',
    ]);
    expect(outcome.opened[live.session.id]?.session.id, 'srv-1');
    expect(outcome.stored.values.map((r) => r.sessionId), ['srv-1', 'srv-1']);
    expect(phone.queue.unsent, isEmpty);
    expect(phone.queue.currentIdOf(live.session.id), 'srv-1');
    await Future<void>.delayed(Duration.zero);
    expect(opened.single.sessionId, live.session.id);
    expect(opened.single.live.session.id, 'srv-1');
    // The copy now holds the server's session, so it reopens under its id.
    expect(phone.copies.values.single.session.id, 'srv-1');
  });

  test('a mark sent with the phone id after the opening went through lands on the server session', () async {
    final server = _IdempotentServer();
    final phone = _Phone(server);
    final live = await phone.opener(_day, {'ari'});
    phone.online = true;
    await phone.queue.flush();

    await _markOn(phone, live, 'ari', 0);

    expect(server.log, ['open srv-1', 'set srv-1 ari 0']);
  });

  test(
    'the sets of a phone session stay queued while its opening cannot go',
    () async {
      final server = _IdempotentServer();
      final phone = _Phone(server);
      final live = await phone.opener(_day, {'ari'});
      await _markOn(phone, live, 'ari', 0);
      // A set of a session the server already had, queued behind.
      server.open('c1', 'a1', _date, 1, 1, const {});
      await phone.queue.submit(
        clubId: 'c1',
        sessionId: 'srv-1',
        write: _mark('ari', 3),
      );

      await phone.queue.flush();
      expect(phone.queue.saveState, SaveState.unsaved);
      expect(phone.queue.pendingOpens, hasLength(1));
      expect(phone.queue.pending, hasLength(2));
    },
  );

  test('an opening the server refuses leaves the queue with the writes of that phone session', () async {
    final server = _IdempotentServer()
      ..refuseOpening = 'La asignación no está activa.';
    final phone = _Phone(server);
    final live = await phone.opener(_day, {'ari'});
    await _markOn(phone, live, 'ari', 0);
    await phone.queue.submitBlockTime(
      clubId: 'c1',
      sessionId: live.session.id,
      write: _time(0),
    );

    phone.online = true;
    final outcome = await phone.queue.flush();

    expect(outcome.rejected.keys, [live.session.id]);
    expect(phone.queue.unsent, isEmpty);
    expect(await phone.queue.resume(live.session.id), isEmpty);
    expect(server.log, isEmpty);
  });

  test('opening the same day again without signal keeps one opening and adds who is present', () async {
    final server = _IdempotentServer();
    final phone = _Phone(server);
    final first = await phone.opener(_day, {'ari'});

    final second = await phone.opener(_day, {'andi'});

    expect(second.session.id, first.session.id);
    expect(second.session.presentAthleteIds, unorderedEquals(['ari', 'andi']));
    expect(
      phone.queue.pendingOpens.single.presentAthleteIds,
      unorderedEquals(['ari', 'andi']),
    );

    phone.online = true;
    await phone.queue.flush();
    expect(
      server.sessions.values.single.presentAthleteIds,
      unorderedEquals(['ari', 'andi']),
    );
  });

  test('present athletes chosen without signal on a session already opened travel with an opening', () async {
    final server = _IdempotentServer();
    final phone = _Phone(server)..online = true;
    final live = await phone.opener(_day, {'ari'});
    expect(live.session.id, 'srv-1');
    expect(phone.queue.pendingOpens, isEmpty);

    phone.online = false;
    final offline = await phone.opener(_day, {'ari', 'andi'});

    expect(offline.session.id, 'srv-1');
    expect(offline.session.presentAthleteIds, unorderedEquals(['ari', 'andi']));
    expect(
      phone.copies.values.single.session.presentAthleteIds,
      unorderedEquals(['ari', 'andi']),
    );
    expect(phone.queue.pendingOpens.single.sessionId, 'srv-1');

    phone.online = true;
    await phone.queue.flush();
    expect(phone.queue.pendingOpens, isEmpty);
    expect(server.log, ['open srv-1', 'open srv-1']);
    expect(
      server.sessions.values.single.presentAthleteIds,
      unorderedEquals(['ari', 'andi']),
    );
  });

  test('with signal, an opening still queued for that day goes out before the session is read', () async {
    final server = _IdempotentServer();
    final phone = _Phone(server);
    final local = await phone.opener(_day, {'ari'});
    await _markOn(phone, local, 'ari', 0);

    phone.online = true;
    final live = await phone.opener(_day, {'ari'});

    expect(live.session.id, 'srv-1');
    expect(live.records.single.setIndex, 0);
    expect(server.log, ['open srv-1', 'set srv-1 ari 0', 'open srv-1']);
  });

  test('two phones that open the same session without signal end in one session with the sets of both', () async {
    final server = _IdempotentServer();
    final ari = _Phone(server);
    final andi = _Phone(server);
    final onAri = await ari.opener(_day, {'ari'});
    final onAndi = await andi.opener(_day, {'andi'});
    expect(onAri.session.id, isNot(onAndi.session.id));

    await _markOn(ari, onAri, 'ari', 0);
    await _markOn(ari, onAri, 'ari', 1);
    await ari.queue.submitBlockTime(
      clubId: 'c1',
      sessionId: onAri.session.id,
      write: _time(0),
    );
    await _markOn(andi, onAndi, 'andi', 0);
    await _markOn(andi, onAndi, 'ari', 1); // the same set, from the other phone
    await andi.queue.submitBlockTime(
      clubId: 'c1',
      sessionId: onAndi.session.id,
      write: _time(1),
    );

    andi.online = true;
    await andi.queue.flush();
    ari.online = true;
    await ari.queue.flush();

    expect(server.sessions, hasLength(1));
    final session = server.sessions.values.single;
    expect(session.presentAthleteIds, unorderedEquals(['ari', 'andi']));
    expect(
      server.recordsOf(session.id).map((r) => '${r.athleteId} ${r.setIndex}'),
      unorderedEquals(['ari 0', 'ari 1', 'andi 0']),
    );
    expect(server.times.values.map((t) => t.$1), [session.id, session.id]);
    expect(ari.queue.unsent, isEmpty);
    expect(andi.queue.unsent, isEmpty);
    expect(ari.queue.currentIdOf(onAri.session.id), session.id);
    expect(andi.queue.currentIdOf(onAndi.session.id), session.id);
  });

  test('the opening survives a reload with its writes behind it', () async {
    final server = _IdempotentServer();
    final disk = DraftDisk();
    final phone = _Phone(server, disk);
    final live = await phone.opener(_day, {'ari'});
    await _markOn(phone, live, 'ari', 0);

    phone.reload();
    await phone.queue.ready;
    expect(phone.queue.pendingOpens.single.sessionId, live.session.id);
    phone.online = true;
    await phone.queue.flush();

    expect(server.log, ['open srv-1', 'set srv-1 ari 0']);
    expect(
      applyChanges(phone.copies.values.single, const []).session.id,
      'srv-1',
    );
  });
}
