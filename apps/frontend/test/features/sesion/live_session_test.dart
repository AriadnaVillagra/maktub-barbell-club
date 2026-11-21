import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/asignacion/domain/calendar_repository.dart';
import 'package:maktub_frontend/features/atletas/presentation/providers.dart';
import 'package:maktub_frontend/features/sesion/domain/live_session_sync.dart';
import 'package:maktub_frontend/features/sesion/domain/session_repository.dart';
import 'package:maktub_frontend/features/sesion/domain/set_write.dart';
import 'package:maktub_frontend/features/sesion/presentation/providers.dart';

import 'draft_fakes.dart';
import 'live_fakes.dart';

final _data = SessionDayData(
  clubId: 'c1',
  memberIds: const ['ari', 'andi'],
  ownerLabel: 'Grupo Barra',
  location: CalendarLocation(
    assignmentId: 'a1',
    planId: 'p1',
    startDate: DateTime.utc(2026, 9, 1),
    cycle: 3,
    week: 4,
  ),
  plan: PublishedPlanView(
    id: 'p1',
    name: 'Fuerza',
    type: PlanType.regular,
    publishedAt: DateTime.utc(2026, 11, 1),
    weekAssignment: const ['A', 'A', 'A', 'A'],
    weekModels: const [
      WeekModel(id: 'A', name: 'Carga', days: [PlanDay()]),
    ],
  ),
  exerciseNames: const {'sq': 'Sentadilla'},
  athleteNames: const {},
  openingDay: 1,
);

SetWrite _mark(String athlete, int set, {SetRecord? current, double? kg}) {
  final w = SetWrite.of(
    current,
    athleteId: athlete,
    blockIndex: 0,
    prescriptionIndex: 0,
    setIndex: set,
    adjustment: 0,
  ).markedDone();
  return kg == null ? w : w.edited(manualKg: kg, reps: null);
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

/// One phone in the session: its own providers, draft and queue, on the shared [server].
class _Phone {
  _Phone(FakeLiveServer server, {MemoryDraftStore? draft})
    : draft = draft ?? MemoryDraftStore() {
    container = ProviderContainer(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(FakeLiveSessions(server)),
        liveChannelProvider.overrideWithValue(FakeLiveChannel(server)),
        liveReconnectBackoffProvider.overrideWithValue(const [Duration.zero]),
        sessionDraftStoreProvider.overrideWithValue(this.draft),
        todayProvider.overrideWithValue(DateTime.utc(2026, 11, 18)),
      ],
    );
    container.listen(sessionScreenProvider, (_, _) {});
  }

  late final ProviderContainer container;
  final MemoryDraftStore draft;

  SessionScreenController get screen =>
      container.read(sessionScreenProvider.notifier);
  SessionScreenState get state => container.read(sessionScreenProvider);

  Future<void> open() => screen.ensureSession(_data, {'ari', 'andi'});

  Future<void> mark(String athlete, int set, {double? kg}) => screen.writeSet(
    'c1',
    _mark(athlete, set, current: record(athlete, set), kg: kg),
  );

  SetRecord? record(String athlete, int set) => state.live?.records
      .where((r) => r.athleteId == athlete && r.setIndex == set)
      .firstOrNull;

  Set<(String, int)> get marked => {
    for (final r in state.live?.records ?? const <SetRecord>[])
      if (r.done) (r.athleteId, r.setIndex),
  };

  void dispose() => container.dispose();
}

void main() {
  late FakeLiveServer server;
  final phones = <_Phone>[];

  _Phone phone({MemoryDraftStore? draft}) {
    final p = _Phone(server, draft: draft);
    phones.add(p);
    return p;
  }

  setUp(() => server = FakeLiveServer());
  tearDown(() async {
    for (final p in phones) {
      p.dispose();
    }
    phones.clear();
    await _settle();
  });

  test('a set marked on one phone appears on the other', () async {
    final a = phone();
    final b = phone();
    await a.open();
    await b.open();
    await _settle();
    expect(b.state.liveStatus, LiveStatus.live);

    await a.mark('ari', 0);
    await _settle();

    expect(b.marked, {('ari', 0)});
    expect(
      b.record('ari', 0)!.kg,
      100,
      reason: 'with the kilos the server computed',
    );
    expect(a.marked, {('ari', 0)});
  });

  test('cutting the connection and reconnecting loses no marks', () async {
    final a = phone();
    final b = phone();
    await a.open();
    await b.open();
    await _settle();

    server.drop(); // 1006, from Cloud Run or the network
    // A marks before B is back: nobody is connected, so only the resync can bring it.
    await a.mark('ari', 0);
    await a.mark('andi', 1, kg: 80);
    await _settle();

    expect(b.state.liveStatus, LiveStatus.live);
    expect(b.marked, {('ari', 0), ('andi', 1)});
    expect(b.record('andi', 1)!.kg, 80);
  });

  test('reloading loses no marks and keeps following', () async {
    final a = phone();
    final draft = MemoryDraftStore();
    final b = phone(draft: draft);
    await a.open();
    await b.open();
    await _settle();
    await a.mark('ari', 0);
    await _settle();

    b.dispose(); // the reload
    phones.remove(b);
    await a.mark('ari', 1);
    final reloaded = phone(draft: MemoryDraftStore(draft.disk));
    await reloaded.open();
    await _settle();
    await a.mark('andi', 0);
    await _settle();

    expect(reloaded.marked, {('ari', 0), ('ari', 1), ('andi', 0)});
    expect(
      server.resyncsFrom.last,
      2,
      reason: 'from the number it opened with',
    );
  });

  test('while the channel does not answer, marking still works', () async {
    server.hanging = true; // the service starting cold, or the socket stuck
    final a = phone();
    await a.open();
    await _settle();
    expect(a.state.liveStatus, LiveStatus.connecting);

    await a.mark('ari', 0);

    expect(a.marked, {('ari', 0)});
    expect(a.record('ari', 0)!.kg, 100);
    expect(server.records, hasLength(1));
  });

  test(
    'a change from another phone does not undo a mark still queued here',
    () async {
      final a = phone();
      final b = phone();
      await a.open();
      await b.open();
      await _settle();

      server.writesDown = true; // A loses signal for writes only
      await a.mark('ari', 0, kg: 90);
      expect(a.record('ari', 0)!.kg, 90);
      server.writesDown = false;
      await b.mark('ari', 0, kg: 85);
      await _settle();
      expect(
        a.record('ari', 0)!.kg,
        90,
        reason: 'what A typed stays while queued',
      );

      // The queue goes out when the channel opens again, and A's write wins as the later one.
      server.drop();
      await _settle();

      expect(a.state.liveStatus, LiveStatus.live);
      expect(server.records.values.single.kg, 90);
      expect(a.record('ari', 0)!.kg, 90);
      expect(b.record('ari', 0)!.kg, 90);
    },
  );

  test('choosing another day stops following the session', () async {
    final a = phone();
    await a.open();
    await _settle();
    expect(server.openConnections, 1);

    a.screen.selectDay(3, 1);
    await _settle();

    expect(server.openConnections, 0);
    expect(a.state.live, isNull);

    // Back to its day, the session is taken again, without opening it.
    a.screen.selectDay(4, 1);
    await _settle();

    expect(server.openConnections, 1);
    expect(a.state.live?.session.id, server.sessionId);
  });

  test(
    'the day on screen is the session\'s, even when the D13 day moved on',
    () {
      final twoDays = SessionDayData(
        clubId: _data.clubId,
        memberIds: _data.memberIds,
        ownerLabel: _data.ownerLabel,
        location: _data.location,
        plan: PublishedPlanView(
          id: 'p1',
          name: 'Fuerza',
          type: PlanType.regular,
          publishedAt: DateTime.utc(2026, 11, 1),
          weekAssignment: const ['A', 'A', 'A', 'A'],
          weekModels: const [
            WeekModel(id: 'A', name: 'Carga', days: [PlanDay(), PlanDay()]),
          ],
        ),
        exerciseNames: _data.exerciseNames,
        athleteNames: _data.athleteNames,
        // Day 1 got its first set done, so D13 now opens day 2.
        openingDay: 2,
      );
      final live = LiveSession(
        session: FakeLiveServer().session,
        records: const [],
      );

      expect(shownDayOf(twoDays, const SessionScreenState()), (
        week: 4,
        day: 2,
      ));
      expect(shownDayOf(twoDays, SessionScreenState(live: live)), (
        week: 4,
        day: 1,
      ));
    },
  );
}
