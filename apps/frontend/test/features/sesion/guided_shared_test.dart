import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/asignacion/domain/calendar_repository.dart';
import 'package:maktub_frontend/features/atletas/presentation/providers.dart';
import 'package:maktub_frontend/features/sesion/domain/guided_session.dart';
import 'package:maktub_frontend/features/sesion/presentation/providers.dart';

import 'draft_fakes.dart';
import 'live_fakes.dart';

const _two = [PlanSet(reps: 5, pct: 80), PlanSet(reps: 5, pct: 80)];

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
      WeekModel(
        id: 'A',
        name: 'Carga',
        days: [
          PlanDay(
            blocks: [
              // 0: two sets, simultaneous: one step per set with both athletes.
              PlanBlock(
                name: 'Principal',
                categoryId: 'primario',
                prescriptions: [Prescription(exerciseId: 'sq', sets: _two)],
              ),
              // 1: no sets, done whole.
              PlanBlock(name: 'Movilidad', categoryId: 'estiramiento'),
              // 2: no sets either.
              PlanBlock(name: 'Vuelta a la calma', categoryId: 'estiramiento'),
            ],
          ),
        ],
      ),
    ],
  ),
  exerciseNames: const {'sq': 'Sentadilla'},
  athleteNames: const {},
  openingDay: 1,
  ownAthleteId: 'ari',
);

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

/// The wall clock both phones read.
var _now = DateTime.utc(2026, 11, 18, 10);

/// One phone in the session: its own providers, draft and queue, on the shared [server].
class _Phone {
  _Phone(FakeLiveServer server, {MemoryDraftStore? draft, String passId = 'p'})
    : draft = draft ?? MemoryDraftStore() {
    container = ProviderContainer(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(FakeLiveSessions(server)),
        liveChannelProvider.overrideWithValue(FakeLiveChannel(server)),
        liveReconnectBackoffProvider.overrideWithValue(const [Duration.zero]),
        sessionDraftStoreProvider.overrideWithValue(this.draft),
        todayProvider.overrideWithValue(DateTime.utc(2026, 11, 18)),
        sessionDayProvider.overrideWith((ref) async => _data),
        guidedClockProvider.overrideWithValue(() => _now),
        guidedPassIdProvider.overrideWithValue(() => passId),
      ],
    );
    container.listen(sessionScreenProvider, (_, _) {});
    container.listen(sessionDayProvider, (_, _) {});
  }

  late final ProviderContainer container;
  final MemoryDraftStore draft;

  Future<void> open() async {
    await container.read(sessionDayProvider.future);
    await container
        .read(sessionScreenProvider.notifier)
        .ensureSession(_data, {'ari', 'andi'});
  }

  /// Opens the guided mode, which stays open until [leave].
  ProviderSubscription<GuidedSession?>? _guided;
  void enter() => _guided = container.listen(guidedProvider, (_, _) {});
  void leave() => _guided?.close();

  GuidedController get guided => container.read(guidedProvider.notifier);
  GuidedSession get g => container.read(guidedProvider)!;
  GuidedStep? get step => g.currentStep(guided.recorded);

  void dispose() => container.dispose();
}

void main() {
  late FakeLiveServer server;
  final phones = <_Phone>[];

  _Phone phone({MemoryDraftStore? draft, String passId = 'p'}) {
    final p = _Phone(server, draft: draft, passId: passId);
    phones.add(p);
    return p;
  }

  /// Two phones in the session, both in the guided mode, Ari and Andi chosen on [a].
  Future<(_Phone, _Phone)> pair() async {
    final a = phone(passId: 'pa');
    final b = phone(passId: 'pb');
    await a.open();
    await b.open();
    await _settle();
    a.enter();
    b.enter();
    a.guided.toggleAthlete('andi');
    return (a, b);
  }

  setUp(() {
    server = FakeLiveServer();
    _now = DateTime.utc(2026, 11, 18, 10);
  });
  tearDown(() async {
    for (final p in phones) {
      p.dispose();
    }
    phones.clear();
    await _settle();
  });

  test('beginning on one phone shows the running block on the other, with the same clock', () async {
    final (a, b) = await pair();
    expect(b.g.phase, GuidedPhase.athletes);

    await a.guided.begin();
    await _settle();
    expect(b.g.phase, GuidedPhase.blocks, reason: 'B joins without choosing');
    expect(b.g.athleteIds, ['ari', 'andi']);

    a.guided.startBlock();
    await _settle();
    _now = _now.add(const Duration(minutes: 3, seconds: 7));

    expect(b.g.run!.status, GuidedBlockStatus.running);
    expect(b.g.block!.name, 'Principal');
    expect(b.g.elapsed(_now), const Duration(minutes: 3, seconds: 7));
    expect(b.g.elapsed(_now), a.g.elapsed(_now));
    expect(b.g.run!.start, a.g.run!.start);
    expect(b.step, a.step);
  });

  test('finishing a set on one phone moves the step on the other', () async {
    final (a, b) = await pair();
    await a.guided.begin();
    a.guided.startBlock();
    await _settle();
    expect(b.step!.set, 0);

    await a.guided.finishStep();
    await _settle();

    expect(server.records, hasLength(2));
    expect(a.step!.set, 1);
    expect(b.step!.set, 1, reason: 'the step follows on B');

    await b.guided.finishStep(); // the last set, from the other phone
    await _settle();

    expect(a.g.block!.name, 'Movilidad', reason: 'the block closed on both');
    expect(b.g.block!.name, 'Movilidad');
    expect(a.g.run!.status, GuidedBlockStatus.pending);
    expect(server.times.keys, ['pa-0']);
  });

  test('skipping or finishing a block on one phone moves the other', () async {
    final (a, b) = await pair();
    await a.guided.begin();
    await _settle();

    b.guided.skipBlock();
    await _settle();
    expect(a.g.block!.name, 'Movilidad');

    a.guided.startBlock();
    await _settle();
    expect(b.g.run!.status, GuidedBlockStatus.running);
    await b.guided.finishBlock();
    await _settle();

    expect(a.g.block!.name, 'Vuelta a la calma');
    expect(server.guidedPass!.blocks.map((r) => r.status), [
      GuidedBlockStatus.skipped,
      GuidedBlockStatus.done,
      GuidedBlockStatus.pending,
    ]);
  });

  test('finishing the day takes both phones to the summary', () async {
    final (a, b) = await pair();
    await a.guided.begin();
    a.guided.startBlock();
    await _settle();

    b.guided.finishDay();
    await _settle();

    expect(a.g.phase, GuidedPhase.finished);
    expect(b.g.phase, GuidedPhase.finished);
    expect(a.g.runs[0].status, GuidedBlockStatus.interrupted);
  });

  test('leaving on one phone does not finish the pass for the other', () async {
    final (a, b) = await pair();
    await a.guided.begin();
    a.guided.startBlock();
    await _settle();

    a.leave();
    await _settle();
    b.guided.skipExercise();
    await _settle();

    expect(server.guidedPass!.finished, false);
    a.enter();
    expect(a.g.phase, GuidedPhase.blocks, reason: 'entering again resumes it');
    expect(a.g.block!.name, b.g.block!.name);
  });

  test(
    'two phones finishing the same block at once: one close, one block time',
    () async {
      final (a, b) = await pair();
      await a.guided.begin();
      a.guided.skipBlock();
      a.guided.startBlock();
      await _settle();
      final changes = server.passChanges;

      // Both tap "Terminar bloque" before either hears of the other.
      _now = _now.add(const Duration(minutes: 2));
      final first = a.guided.finishBlock();
      _now = _now.add(const Duration(seconds: 1));
      final second = b.guided.finishBlock();
      await Future.wait([first, second]);
      await _settle();

      expect(server.passChanges - changes, 1);
      expect(server.times.keys, ['pa-1'], reason: 'one time, by the pass id');
      expect(
        server.guidedPass!.blocks[1].end,
        DateTime.utc(2026, 11, 18, 10, 2),
      );
      expect(a.g.block!.name, 'Vuelta a la calma');
      expect(b.g.block!.name, 'Vuelta a la calma');
    },
  );

  test('without signal the pass goes on on the phone and reaches the server when it returns', () async {
    final (a, b) = await pair();
    server.writesDown = true;

    await a.guided.begin();
    a.guided.startBlock();
    await a.guided.finishStep();
    await _settle();

    expect(server.guidedPass, isNull);
    expect(a.g.block!.name, 'Principal');
    expect(a.step!.set, 1, reason: 'the phone moves on by itself');
    expect(b.g.phase, GuidedPhase.athletes);

    server.writesDown = false;
    server.drop(); // the channel opens again and the queue goes out
    await _settle();
    await _settle();

    expect(server.records, hasLength(2));
    expect(server.guidedPass!.blocks[0].status, GuidedBlockStatus.running);
    expect(b.g.phase, GuidedPhase.blocks);
    expect(b.step!.set, 1);
    expect(a.step!.set, 1);
  });

  test('reloading in the middle comes back to the same block and step, even with writes still queued', () async {
    final draft = MemoryDraftStore();
    final a = phone(draft: draft, passId: 'pa');
    await a.open();
    await _settle();
    a.enter();
    a.guided.toggleAthlete('andi');
    await a.guided.begin();
    a.guided.skipBlock();
    await _settle();
    server.writesDown = true; // what follows stays queued on the device
    a.guided.skipBlock();
    a.guided.startBlock();
    await _settle();
    expect(a.g.block!.name, 'Vuelta a la calma');

    a.dispose(); // the reload
    phones.remove(a);
    final reloaded = phone(draft: MemoryDraftStore(draft.disk), passId: 'pz');
    await reloaded.open();
    await _settle();
    reloaded.enter();

    expect(reloaded.g.phase, GuidedPhase.blocks);
    expect(reloaded.g.block!.name, 'Vuelta a la calma');
    expect(reloaded.g.run!.status, GuidedBlockStatus.running);
    expect(server.guidedPass!.current, 1, reason: 'the server is behind');

    server.writesDown = false;
    server.drop();
    await _settle();
    await _settle();
    expect(server.guidedPass!.current, 2);
    expect(reloaded.g.block!.name, 'Vuelta a la calma');
  });

  test(
    'reloading with nothing queued resumes from the server, on the same step',
    () async {
      final (a, _) = await pair();
      await a.guided.begin();
      a.guided.startBlock();
      await a.guided.finishStep();
      await _settle();

      final reloaded = phone(passId: 'pz');
      await reloaded.open();
      await _settle();
      reloaded.enter();

      expect(reloaded.g.block!.name, 'Principal');
      expect(reloaded.step!.set, 1);
      expect(reloaded.g.start, a.g.start);
    },
  );
}
