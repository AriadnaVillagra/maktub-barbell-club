import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/core/offline/local_copy.dart';
import 'package:maktub_frontend/core/offline/local_copy_providers.dart';
import 'package:maktub_frontend/core/offline/shared_preferences_local_copy_store.dart';
import 'package:maktub_frontend/features/access/presentation/providers.dart';
import 'package:maktub_frontend/features/asignacion/presentation/calendar_providers.dart';
import 'package:maktub_frontend/features/asignacion/presentation/providers.dart';
import 'package:maktub_frontend/features/atletas/presentation/providers.dart';
import 'package:maktub_frontend/features/catalogo/presentation/providers.dart';
import 'package:maktub_frontend/features/sesion/data/cached_session_repository.dart';
import 'package:maktub_frontend/features/sesion/domain/athlete_adjustments.dart';
import 'package:maktub_frontend/features/sesion/domain/session_repository.dart';
import 'package:maktub_frontend/features/sesion/domain/set_write.dart';
import 'package:maktub_frontend/features/sesion/presentation/providers.dart';
import 'package:maktub_frontend/features/sesion/presentation/session_page.dart';
import 'package:maktub_frontend/features/session/presentation/providers.dart';
import 'package:maktub_ui/maktub_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../access/fakes.dart';
import '../catalogo/catalog_fakes.dart';
import '../session/fakes.dart';
import 'draft_fakes.dart';
import 'live_fakes.dart';
import 'offline_fakes.dart';

// 2026-11-18 is cycle 3, week 4 (model B); 2026-11-24 is cycle 4, week 1 (model A), inside the preload of the 18th.
final _preloadDay = DateTime.utc(2026, 11, 18);
final _laterDay = DateTime.utc(2026, 11, 24);

/// The fake server, the same across "reloads" of the app; what the app keeps between them is only the storage.
class _Server {
  final signal = Signal();
  late final me = OfflineMe(
    signal,
    meWith(
      [
        (club('c1', 'Gimnasio', TipoClub.club), {Rol.coach, Rol.atleta}),
      ],
      athleteIds: {'c1': 'ari'},
    ),
  );
  late final calendar = OfflineCalendar(signal);
  late final sessions = OfflineSessions(signal);
  late final proposedDays = OfflineProposedDays(signal);
  final tokens = FakeTokenStore(issued(1));

  /// Another phone's writes reach this one through this channel.
  final live = FakeLiveServer();

  /// The queue's storage, kept across reloads like the rest of the device's storage.
  final draftDisk = DraftDisk();
  final auth = FakeAuthApi();

  List<Override> overrides(DateTime today, {LocalCopyStore? store}) => [
    tokenStoreProvider.overrideWithValue(tokens),
    authApiProvider.overrideWithValue(auth),
    remoteMeRepositoryProvider.overrideWithValue(me),
    remoteAssignmentRepositoryProvider.overrideWithValue(OfflineGroups(signal)),
    remoteCalendarRepositoryProvider.overrideWithValue(calendar),
    remoteCatalogRepositoryProvider.overrideWithValue(OfflineCatalog(signal)),
    remoteCatalogAdminRepositoryProvider.overrideWithValue(
      OfflineCatalogAdmin(signal),
    ),
    remoteAthleteRepositoryProvider.overrideWithValue(OfflineAthletes(signal)),
    remoteSessionRepositoryProvider.overrideWithValue(sessions),
    remoteProposedDaysRepositoryProvider.overrideWithValue(proposedDays),
    liveChannelProvider.overrideWithValue(FakeLiveChannel(live)),
    sessionDraftStoreProvider.overrideWithValue(MemoryDraftStore(draftDisk)),
    todayProvider.overrideWithValue(today),
    if (store != null) localCopyStoreProvider.overrideWithValue(store),
  ];

  /// The app starting with a session on [today]: the saved token restores it and the preload runs.
  Future<void> preload(DateTime today) async {
    final container = ProviderContainer(overrides: overrides(today));
    await container.read(sessionManagerProvider).restore();
    await container.read(preloadDaysProvider.future);
    container.dispose();
  }
}

/// Starts the app afresh on [today] with the session screen: a new scope, so nothing is kept but the storage.
Future<void> _launch(
  WidgetTester tester,
  _Server server,
  DateTime today, {
  LocalCopyStore? store,
}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: server.overrides(today, store: store),
      child: MaterialApp(
        theme: TemaMaktub.para(Brightness.dark, Densidad.entrenamiento),
        home: const SessionPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

bool _checked(WidgetTester tester, String id) =>
    (tester.widget<IconButton>(find.byKey(Key('session-check-$id'))).icon
            as Icon)
        .icon ==
    Icons.check_circle;

String _kg(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'after a preload, without signal the calendar and the day of a preloaded date open',
    (tester) async {
      final server = _Server();
      await server.preload(_preloadDay);
      expect(server.proposedDays.ranges, [
        (_preloadDay, _preloadDay.add(const Duration(days: 7))),
      ]);

      server.signal.on = false;
      await _launch(tester, server, _laterDay);

      expect(find.text('Fuerza · ciclo 4 · semana 1'), findsOneWidget);
      expect(find.text('Día 1 · Piernas'), findsOneWidget);
      expect(find.text('Sentadilla'), findsOneWidget);
      expect(find.byKey(const Key('local-copy-notice')), findsOneWidget);
      expect(
        find.textContaining('Sin señal · datos guardados el'),
        findsOneWidget,
      );

      await tester.tap(find.text('Calendario'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar-summary')), findsOneWidget);
      expect(find.byKey(const Key('calendar-day-2-1')), findsOneWidget);
    },
  );

  testWidgets(
    'without signal, the kilos the preload saved serve a session of that date',
    (tester) async {
      final server = _Server();
      await server.preload(_preloadDay);
      server.signal.on = false;
      final container = ProviderContainer(
        overrides: server.overrides(_laterDay),
      );
      addTearDown(container.dispose);
      final repository =
          container.read(sessionRepositoryProvider) as CachedSessionRepository;
      // A session opened on the device (E7.16), handed over as the app does.
      await repository.remember(
        LiveSession(
          session: Session(
            id: 'local-1',
            clubId: 'c1',
            assignmentId: 'a1',
            planId: 'p1',
            cycle: 4,
            week: 1,
            day: 1,
            date: _laterDay,
            presentAthleteIds: const ['ari', 'andi'],
            auditoria: audit(),
          ),
          records: const [],
        ),
      );

      final ari = await repository.proposedLoads(
        'c1',
        'local-1',
        'ari',
        const AthleteAdjustments(),
      );
      final andi = await repository.proposedLoads(
        'c1',
        'local-1',
        'andi',
        const AthleteAdjustments(),
      );

      expect(ari.map((s) => s.kg), [82.5, 82.5]);
      // With signal too: the server does not know a session opened on the device until its opening goes through.
      server.signal.on = true;
      expect(
        (await repository.proposedLoads(
          'c1',
          'local-1',
          'ari',
          const AthleteAdjustments(),
        )).map((s) => s.kg),
        [82.5, 82.5],
      );
      server.signal.on = false;
      expect(andi.map((s) => s.kg), [62.5, 62.5]);
      expect(container.read(localCopyNoticeProvider), isNotNull);
      await expectLater(
        repository.proposedLoads(
          'c1',
          'local-1',
          'ari',
          const AthleteAdjustments(session: 110),
        ),
        throwsA(
          isA<NoLocalCopy>().having(
            (e) => e.mensaje,
            'mensaje',
            CachedSessionRepository.offlineAdjustmentMessage,
          ),
        ),
      );
    },
  );

  test('the copy keeps the guided pass, written here or arriving over the channel, and opens with it without signal', () async {
    final server = _Server();
    final container = ProviderContainer(overrides: server.overrides(_laterDay));
    addTearDown(container.dispose);
    final repository =
        container.read(sessionRepositoryProvider) as CachedSessionRepository;
    Future<LiveSession> open() => repository.open(
      'c1',
      assignmentId: 'a1',
      date: _laterDay,
      week: 1,
      day: 1,
      presentAthleteIds: const {'ari'},
    );
    final opened = await open();

    await repository.writeGuidedPass(
      'c1',
      opened.session.id,
      GuidedPassAction.begin(
        passId: 'p1',
        version: 0,
        at: DateTime.utc(2026, 11, 24, 10),
        athleteIds: const ['ari'],
        blocks: const [
          GuidedBlockStart(
            athleteMode: AthleteMode.simultaneous,
            executionMode: ExecutionMode.sequential,
          ),
        ],
      ),
    );
    server.signal.on = false;
    expect((await open()).session.guidedPass?.id, 'p1');

    // Another phone started the block: the change arrives over the channel.
    final started = applyGuidedAction(
      server.sessions.pass,
      GuidedPassAction.onBlock(
        GuidedActionKind.startBlock,
        passId: 'p1',
        version: 1,
        at: DateTime.utc(2026, 11, 24, 10, 1),
        block: 0,
      ),
    )!;
    await repository.applyChanges('c1', opened.session.id, [
      SessionChange.ofSession(
        9,
        Session.fromJson({
          ...opened.session.toJson(),
          'secuencia': 9,
          'secuenciaSesion': 9,
          'pasadaGuiada': started.toJson(),
        }),
      ),
    ]);

    final again = await open();
    expect(
      again.session.guidedPass!.blocks.single.status,
      GuidedBlockStatus.running,
    );
  });

  testWidgets(
    'a session opened with signal opens again without signal, with its kilos',
    (tester) async {
      final server = _Server();
      await _launch(tester, server, _laterDay);
      await tester.tap(find.byKey(const Key('session-open')));
      await tester.pumpAndSettle();
      expect(_kg(tester, 'session-kg-0-0-0'), '90 kg');
      expect(find.byKey(const Key('local-copy-notice')), findsNothing);

      server.signal.on = false;
      await _launch(tester, server, _laterDay);
      await tester.tap(find.byKey(const Key('session-open')));
      await tester.pumpAndSettle();

      expect(_kg(tester, 'session-kg-0-0-0'), '90 kg');
      expect(_kg(tester, 'session-kg-0-0-1'), '90 kg');
      expect(find.byKey(const Key('local-copy-notice')), findsOneWidget);

      // The adjustment's kilos come from the server: without signal it says so instead of guessing.
      await tester.tap(find.byKey(const Key('session-adjust-session-plus')));
      await tester.pumpAndSettle();
      expect(
        find.text(CachedSessionRepository.offlineAdjustmentMessage),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('session-adjust-session-reset')));
      await tester.pumpAndSettle();
      expect(_kg(tester, 'session-kg-0-0-0'), '90 kg');
    },
  );

  testWidgets('without signal a session never opened here opens on the phone, keeps its marks on reload and '
      'goes up when signal returns', (tester) async {
    final server = _Server();
    await server.preload(_preloadDay);
    server.signal.on = false;
    await _launch(tester, server, _laterDay);

    await tester.tap(find.byKey(const Key('session-open')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('session-opened-offline')), findsOneWidget);
    expect(find.byKey(const Key('session-live-connecting')), findsNothing);
    expect(_kg(tester, 'session-kg-0-0-0'), '82.5 kg'); // the preloaded kilos
    await tester.tap(find.byKey(const Key('session-check-0-0-0')));
    await tester.pumpAndSettle();
    expect(_checked(tester, '0-0-0'), isTrue);

    // Reload without signal: the session opened on the phone and its mark are still there.
    await _launch(tester, server, _laterDay);
    await tester.tap(find.byKey(const Key('session-open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('session-opened-offline')), findsOneWidget);
    expect(_checked(tester, '0-0-0'), isTrue);
    expect(_checked(tester, '0-0-1'), isFalse);
    await tester.tap(find.byKey(const Key('session-check-0-0-1')));
    await tester.pumpAndSettle();
    expect(server.sessions.log, isEmpty);

    // Signal returns: the opening goes first, then the sets with the server's id, and the screen moves to it.
    server.signal.on = true;
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SessionPage)),
    );
    await tester.runAsync(() => container.read(setSyncQueueProvider).flush());
    await tester.pumpAndSettle();

    expect(server.sessions.log, [
      'open ari',
      'set s1 ari 0 true',
      'set s1 ari 1 true',
    ]);
    expect(container.read(setSyncQueueProvider).unsent, isEmpty);
    expect(container.read(sessionScreenProvider).live?.session.id, 's1');
    expect(find.byKey(const Key('session-opened-offline')), findsNothing);
    expect(_checked(tester, '0-0-0'), isTrue);
    expect(_checked(tester, '0-0-1'), isTrue);
  });

  testWidgets(
    'what another phone marks arrives through the channel and is kept for opening without signal',
    (tester) async {
      final server = _Server();
      await _launch(tester, server, _laterDay);
      await tester.tap(find.byKey(const Key('session-open')));
      await tester.pumpAndSettle();
      expect(_checked(tester, '0-0-1'), isFalse);

      server.live.write(
        SetWrite.of(
          null,
          athleteId: 'ari',
          blockIndex: 0,
          prescriptionIndex: 0,
          setIndex: 1,
          adjustment: Ajuste.neutro,
        ).toggled(),
      );
      await tester.pumpAndSettle();
      expect(_checked(tester, '0-0-1'), isTrue);

      server.signal.on = false;
      server.live.down = true;
      await _launch(tester, server, _laterDay);
      await tester.tap(find.byKey(const Key('session-open')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('local-copy-notice')), findsOneWidget);
      expect(_checked(tester, '0-0-1'), isTrue);
      expect(_checked(tester, '0-0-0'), isFalse);
    },
  );

  testWidgets('a date neither preloaded nor seen shows a clear message', (
    tester,
  ) async {
    final server = _Server();
    await server.preload(_preloadDay);
    server.signal.on = false;
    await _launch(tester, server, DateTime.utc(2026, 12, 10));

    expect(
      find.textContaining('Sin señal y sin datos guardados del 10/12'),
      findsOneWidget,
    );
    expect(find.text('No se pudo cargar.'), findsNothing);
  });

  testWidgets('with signal the data is fresh and the copy is updated', (
    tester,
  ) async {
    final server = _Server();
    await server.preload(_preloadDay);
    server.calendar.planName = 'Fuerza 2';

    await _launch(tester, server, _laterDay);
    expect(find.text('Fuerza 2 · ciclo 4 · semana 1'), findsOneWidget);
    expect(find.byKey(const Key('local-copy-notice')), findsNothing);

    server.signal.on = false;
    await _launch(tester, server, _laterDay);
    expect(find.text('Fuerza 2 · ciclo 4 · semana 1'), findsOneWidget);
    expect(find.byKey(const Key('local-copy-notice')), findsOneWidget);
  });

  testWidgets('without storage the app works as before', (tester) async {
    final server = _Server();
    final store = SharedPreferencesLocalCopyStore(
      preferences: () async => throw Exception('storage blocked'),
    );
    await _launch(tester, server, _laterDay, store: store);

    expect(find.text('Fuerza · ciclo 4 · semana 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('session-open')));
    await tester.pumpAndSettle();
    expect(_kg(tester, 'session-kg-0-0-0'), '90 kg');

    server.signal.on = false;
    await _launch(tester, server, _laterDay, store: store);
    expect(
      find.textContaining('Sin señal y sin datos guardados'),
      findsOneWidget,
    );
  });
}
