import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_frontend/features/temporizador/presentation/quick_timers_providers.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/app/router.dart' show Rutas;
import 'package:maktub_frontend/features/access/presentation/providers.dart';
import 'package:maktub_frontend/features/asignacion/domain/assignment_repository.dart';
import 'package:maktub_frontend/features/asignacion/domain/calendar_repository.dart';
import 'package:maktub_frontend/features/asignacion/presentation/calendar_providers.dart';
import 'package:maktub_frontend/features/asignacion/presentation/providers.dart';
import 'package:maktub_frontend/features/atletas/domain/athlete_repository.dart';
import 'package:maktub_frontend/features/atletas/presentation/providers.dart';
import 'package:maktub_frontend/features/catalogo/presentation/providers.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/sesion/domain/athlete_adjustments.dart';
import 'package:maktub_frontend/features/sesion/data/shared_preferences_guided_position_store.dart';
import 'package:maktub_frontend/features/sesion/domain/block_time_write.dart';
import 'package:maktub_frontend/features/sesion/domain/guided_position.dart';
import 'package:maktub_frontend/features/sesion/domain/session_repository.dart';
import 'package:maktub_frontend/features/sesion/domain/set_write.dart';
import 'package:maktub_frontend/features/sesion/presentation/guided_page.dart';
import 'package:maktub_frontend/features/sesion/presentation/providers.dart';
import 'package:maktub_frontend/features/sesion/presentation/session_page.dart';
import 'package:maktub_frontend/features/temporizador/presentation/controllers/crono_controller.dart';
import 'package:maktub_frontend/features/temporizador/presentation/providers.dart';
import 'package:maktub_ui/maktub_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../access/fakes.dart';
import '../catalogo/catalog_admin_fakes.dart';
import '../catalogo/catalog_fakes.dart';
import '../temporizador/timer_fakes.dart';
import 'draft_fakes.dart';
import 'live_fakes.dart';

final _today = DateTime.utc(2026, 11, 18);
final _start = DateTime.utc(2026, 9, 1);

const _sq = [PlanSet(reps: 5, pct: 80), PlanSet(reps: 5, pct: 80)];

final _plan = PublishedPlanView(
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
          name: 'Piernas',
          blocks: [
            // 0: no sets, done whole.
            PlanBlock(
              name: 'Movilidad',
              categoryId: 'estiramiento',
              note: 'Hombros',
            ),
            // 1: by turns by default, with its own rest.
            PlanBlock(
              name: 'Principal',
              categoryId: 'primario',
              athleteMode: AthleteMode.turns,
              prescriptions: [
                Prescription(exerciseId: 'sq', timerId: 'rest90', sets: _sq),
              ],
            ),
            // 2: a circuit without rest.
            PlanBlock(
              name: 'Accesorios',
              categoryId: 'accesorio',
              executionMode: ExecutionMode.circuit,
              prescriptions: [
                Prescription(
                  exerciseId: 'curl',
                  sets: [PlanSet(reps: 10), PlanSet(reps: 10)],
                ),
                Prescription(exerciseId: 'face', sets: [PlanSet(reps: 12)]),
              ],
            ),
            // 3: a timed WoD.
            PlanBlock(
              name: 'Cindy',
              categoryId: 'wod',
              executionMode: ExecutionMode.timed,
              timerId: 'amrap',
              note: '20 min AMRAP',
              prescriptions: [
                Prescription(exerciseId: 'pu', sets: [PlanSet(reps: 5)]),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

/// An exercise in kilos (not by % of RM).
final _press = ex('press', 'Press con mancuerna', categories: ['accesorio'], metrics: [Metric.fixedLoad, Metric.reps]);

/// The plan the fake calendar serves; a test can swap it for another.
PublishedPlanView _served = _plan;

PublishedPlanView _planOf(List<PlanBlock> blocks) => PublishedPlanView(
  id: 'p1',
  name: 'Fuerza',
  type: PlanType.regular,
  publishedAt: DateTime.utc(2026, 11, 1),
  weekAssignment: const ['A', 'A', 'A', 'A'],
  weekModels: [
    WeekModel(
      id: 'A',
      name: 'Carga',
      days: [PlanDay(name: 'Piernas', blocks: blocks)],
    ),
  ],
);

class _Groups implements AssignmentRepository {
  @override
  Future<List<AthleteGroup>> groups(String clubId) async => [
    AthleteGroup(
      id: 'g1',
      clubId: clubId,
      name: 'Barra',
      memberIds: const ['ari', 'andi', 'luz'],
      auditoria: audit(),
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Calendar implements CalendarRepository {
  @override
  Future<CalendarLocation?> locate(
    String clubId,
    String groupId,
    DateTime date,
  ) async {
    final where = UbicacionEnCiclo.desdeFechas(inicio: _start, fecha: date);
    return CalendarLocation(
      assignmentId: 'a1',
      planId: 'p1',
      startDate: _start,
      cycle: where.ciclo,
      week: where.semana,
    );
  }

  @override
  Future<List<CalendarLocation>> locateAthlete(
    String clubId,
    String athleteId,
    DateTime date,
  ) async => [?await locate(clubId, 'g1', date)];

  @override
  Future<PublishedPlanView> publishedPlan(String clubId, String planId) async =>
      _served;

  @override
  Future<List<DayState>> dayStates(
    String clubId,
    String groupId,
    DateTime from,
    DateTime to, {
    String? athleteId,
  }) async => _states;
}

/// The day states the fake calendar serves; a test can set them.
List<DayState> _states = const [];

class _Athletes implements AthleteRepository {
  @override
  Future<List<AthleteSummary>> athletes(String clubId) async => const [
    AthleteSummary(id: 'ari', userId: 'u1', name: 'Ari'),
    AthleteSummary(id: 'andi', userId: 'u2', name: 'Andi'),
    AthleteSummary(id: 'luz', userId: 'u3', name: 'Luz'),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Stores sets like the server. The squat is proposed at 80 kg for Ari and 64 kg for Andi.
class _Sessions implements SessionRepository {
  _Sessions({this.records = const []});

  /// What the session already has when it opens, as if another device had marked it.
  final List<SetRecord> records;

  /// What the server has: [records] and every set written since.
  late final stored = [...records];
  final opened = <Set<String>>[];
  final writes = <SetWrite>[];

  /// The block times the server took, in order, with their ids.
  final times = <(String, BlockTimeWrite)>[];

  /// Without signal, block times are not taken.
  bool offline = false;

  /// Without signal, sets are not taken either; they stay in the device's queue.
  bool offlineSets = false;

  /// The session's guided pass (E7.26), as the server keeps it, and its last change number.
  GuidedPass? pass;
  var sessionChanges = 0;

  /// The present athletes of the last opening.
  var present = <String>[];

  /// What the server proposes to each athlete, when a test sets it; else the squat's kilos below.
  List<ProposedSet> Function(String athleteId)? proposals;

  /// The reps the plan has for each prescription.
  static int _planReps(int block, int prescription) =>
      switch ((block, prescription)) {
        (2, 0) => 10,
        (2, 1) => 12,
        _ => 5,
      };

  static double _kg(String athlete) => athlete == 'ari' ? 80 : 64;

  /// Whether the session exists on the server: something was recorded on it, a pass goes on, or it was opened.
  late var exists = records.isNotEmpty || pass != null;

  /// The date the session was opened on: like the server, a session belongs to one date.
  DateTime? date;

  @override
  Future<LiveSession?> find(
    String clubId, {
    required String assignmentId,
    required DateTime date,
    required int week,
    required int day,
  }) async {
    if (!exists || day != 1) return null;
    if (this.date != null && this.date != date) return null;
    if (opened.isEmpty) {
      _week = week;
      present = {for (final r in records) r.athleteId}.toList();
    }
    if (_week != week) return null;
    return LiveSession(session: _session(), records: [...stored]);
  }

  @override
  Future<LiveSession> open(
    String clubId, {
    required String assignmentId,
    required DateTime date,
    required int week,
    required int day,
    required Set<String> presentAthleteIds,
  }) async {
    if (this.date != null && this.date != date) {
      throw StateError('a second session on $date');
    }
    this.date = date;
    opened.add(presentAthleteIds);
    present = {...present, ...presentAthleteIds}.toList();
    _week = week;
    exists = true;
    return LiveSession(session: _session(), records: [...stored]);
  }

  var _week = 1;

  Session _session() => Session(
    id: 's1',
    clubId: 'c1',
    assignmentId: 'a1',
    planId: 'p1',
    cycle: 3,
    week: _week,
    day: 1,
    date: date ?? _today,
    presentAthleteIds: present,
    lastSessionChange: sessionChanges,
    guidedPass: pass,
    auditoria: audit(),
  );

  @override
  Future<Session> writeGuidedPass(
    String clubId,
    String sessionId,
    GuidedPassAction action,
  ) async {
    if (offline) throw const ErrorDeApi('No se pudo conectar.');
    final next = applyGuidedAction(pass, action);
    if (next != null && !identical(next, pass)) {
      pass = next;
      sessionChanges++;
    }
    return _session();
  }

  @override
  Future<List<ProposedSet>> proposedLoads(
    String clubId,
    String sessionId,
    String athleteId,
    AthleteAdjustments adjustments,
  ) async => proposals?.call(athleteId) ?? [
    for (var s = 0; s < 2; s++)
      ProposedSet(
        blockIndex: 1,
        prescriptionIndex: 0,
        setIndex: s,
        exerciseId: 'sq',
        kg: _kg(athleteId),
        appliedPct: 80,
      ),
  ];

  @override
  Future<void> recordBlockTime(
    String clubId,
    String sessionId,
    String timeId,
    BlockTimeWrite write,
  ) async {
    if (offline) throw const ErrorDeApi('No se pudo conectar.');
    times.removeWhere((t) => t.$1 == timeId);
    times.add((timeId, write));
  }

  @override
  Future<SetRecord> recordSet(
    String clubId,
    String sessionId,
    SetWrite write,
  ) async {
    if (offlineSets) throw const ErrorDeApi('No se pudo conectar.');
    writes.add(write);
    final record = _record(
      write.athleteId,
      write.blockIndex,
      write.prescriptionIndex,
      write.setIndex,
      done: write.done,
      kg: write.manualKg ?? _kg(write.athleteId),
      reps: write.reps ?? _planReps(write.blockIndex, write.prescriptionIndex),
      manualKg: write.manualKg != null,
    );
    stored
      ..removeWhere((r) => r.id == record.id)
      ..add(record);
    return record;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

SetRecord _record(
  String athlete,
  int b,
  int p,
  int s, {
  bool done = true,
  double? kg,
  int? reps,
  bool manualKg = false,
}) => SetRecord(
  id: 'r-$athlete-$b-$p-$s',
  clubId: 'c1',
  sessionId: 's1',
  athleteId: athlete,
  exerciseId: 'sq',
  exerciseName: 'Sentadilla',
  blockIndex: b,
  prescriptionIndex: p,
  setIndex: s,
  target: const PlanSet(reps: 5, pct: 80),
  done: done,
  kg: kg,
  reps: reps ?? 5,
  manualKg: manualKg,
  writtenBy: 'u1',
  auditoria: audit(),
);

/// What a write leaves: athlete, block, prescription, set and whether it is done.
String _w(SetWrite w) =>
    '${w.athleteId} ${w.blockIndex}-${w.prescriptionIndex}-${w.setIndex}'
    '${w.done ? ' done' : ''}';

/// Where the device remembers the guided mode's position, in memory.
class _Positions implements GuidedPositionStore {
  GuidedPosition? saved;

  @override
  Future<GuidedPosition?> load() async => saved;

  @override
  Future<void> save(GuidedPosition? position) async => saved = position;
}

class _Harness {
  _Harness(this.sessions);

  final _Sessions sessions;
  final platform = FakeTimerPlatform();
  DateTime now = DateTime.utc(2026, 11, 18, 10);
  late ProviderContainer container;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  List<SetRecord> records = const [],
  GuidedPass? pass,
  _Sessions? sessions,
  DateTime? today,
  GuidedPositionStore? positions,
}) async {
  final h = _Harness(sessions ?? (_Sessions(records: records)..pass = pass));
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final me = meWith(
    [
      (club('c1', 'Gimnasio', TipoClub.club), {Rol.coach}),
    ],
    athleteIds: {'c1': 'ari'},
  );
  final catalog = FakeCatalogAdminRepository(
    exercisesList: [
      ex('sq', 'Sentadilla'),
      ex('curl', 'Curl'),
      ex('face', 'Face pull'),
      ex('pu', 'Dominadas'),
      _press,
    ],
    timersList: [
      timer('rest90', 'Descanso 90', work: 90),
      timer('amrap', 'AMRAP 20', type: TipoTemporizador.amrap, work: 1200),
    ],
  );
  final router = GoRouter(
    initialLocation: Rutas.sesion,
    routes: [
      GoRoute(
        path: Rutas.entrenamiento,
        builder: (_, _) => const SizedBox.shrink(),
        routes: [
          GoRoute(
            path: 'sesion',
            builder: (_, _) => const SessionPage(guidedPath: Rutas.entrenar),
            routes: [
              GoRoute(
                path: 'entrenar',
                builder: (_, _) => const GuidedPage(sessionPath: Rutas.sesion),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        quickTimersRepositoryProvider.overrideWithValue(FakeQuickTimers(['rest90'])),
        meProvider.overrideWith((ref) async => me),
        catalogRepositoryProvider.overrideWithValue(catalog),
        catalogAdminRepositoryProvider.overrideWithValue(catalog),
        assignmentRepositoryProvider.overrideWithValue(_Groups()),
        calendarRepositoryProvider.overrideWithValue(_Calendar()),
        athleteRepositoryProvider.overrideWithValue(_Athletes()),
        sessionRepositoryProvider.overrideWithValue(h.sessions),
        remoteProposedDaysRepositoryProvider.overrideWithValue(
          NoProposedDays(),
        ),
        liveChannelProvider.overrideWithValue(
          FakeLiveChannel(FakeLiveServer()),
        ),
        sessionDraftStoreProvider.overrideWithValue(MemoryDraftStore()),
        todayProvider.overrideWithValue(today ?? _today),
        timerPlatformProvider.overrideWithValue(h.platform),
        guidedClockProvider.overrideWithValue(() => h.now),
        guidedPositionStoreProvider.overrideWithValue(
          positions ?? _Positions(),
        ),
      ],
      child: MaterialApp.router(
        theme: TemaMaktub.para(Brightness.dark, Densidad.entrenamiento),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  h.container = ProviderScope.containerOf(
    tester.element(find.byType(SessionPage)),
  );
  return h;
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// "Saltar bloque" lives in the preview's "Más acciones" sheet.
Future<void> _skipBlock(WidgetTester tester) async {
  await _tap(tester, 'guided-more-actions');
  await _tap(tester, 'guided-skip-block');
}

/// Enters the guided mode from the day's session, which may not exist yet (E7.27).
Future<void> _train(WidgetTester tester) => _tap(tester, 'session-train');

/// Enters with Ari and Andi and goes to the preview of block [block] (0-based), skipping the ones before.
Future<void> _toBlock(WidgetTester tester, int block) async {
  await _train(tester);
  await _tap(tester, 'guided-athlete-andi');
  await _tap(tester, 'guided-begin');
  if (find.byKey(const Key('guided-resume')).evaluate().isNotEmpty) {
    await _tap(tester, 'guided-resume');
  }
  for (var b = 0; b < block; b++) {
    await _skipBlock(tester);
  }
}

/// The text of the widget with [key], or of the one text inside it.
String _text(WidgetTester tester, String key) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(Text),
        matchRoot: true,
      ),
    )
    .data!;

bool _chosen(WidgetTester tester, String key) =>
    tester.widget<PildoraMaktub>(find.byKey(Key(key))).seleccionada;

void main() {
  setUp(() {
    _served = _plan;
    _states = const [];
  });

  group('who trains', () {
    testWidgets('Entrenar starts with the athlete on screen chosen', (
      tester,
    ) async {
      await _pump(tester);
      await _train(tester);

      expect(find.text('¿Quiénes entrenan?'), findsOneWidget);
      expect(_chosen(tester, 'guided-athlete-ari'), true);
      expect(_chosen(tester, 'guided-athlete-andi'), false);
      expect(_chosen(tester, 'guided-athlete-luz'), false);
    });

    testWidgets('it enters without a session; choosing who trains creates '
        'nothing, and "Comenzar" creates it with them (E7.27)', (tester) async {
      final h = await _pump(tester);
      await _train(tester);
      await _tap(tester, 'guided-athlete-luz');
      await _tap(tester, 'guided-athlete-ari');
      await _tap(tester, 'guided-athlete-ari');

      expect(find.text('¿Quiénes entrenan?'), findsOneWidget);
      expect(h.sessions.opened, isEmpty);

      await _tap(tester, 'guided-begin');

      expect(h.sessions.opened, [
        {'ari', 'luz'},
      ]);
      expect(_text(tester, 'guided-block-count'), 'Bloque 1 de 4');
    });

    testWidgets('leaving without "Comenzar" creates nothing', (tester) async {
      final h = await _pump(tester);
      await _train(tester);
      await _tap(tester, 'guided-athlete-andi');
      await _tap(tester, 'guided-exit');
      await tester.tap(find.text('Salir'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('session-train')), findsOneWidget);
      expect(h.sessions.opened, isEmpty);
    });

    testWidgets('an athlete who is not present is added to the session', (
      tester,
    ) async {
      final h = await _pump(tester, records: [_record('ari', 1, 0, 0, done: false)]);
      await _train(tester);
      await _tap(tester, 'guided-athlete-luz');
      await _tap(tester, 'guided-begin');

      expect(h.sessions.opened.last, {'ari', 'luz'});
      expect(h.sessions.present, ['ari', 'luz']);
      expect(_text(tester, 'guided-block-count'), 'Bloque 1 de 4');
    });

    testWidgets('with sets already done it asks; "Seguir" writes nothing', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        records: [_record('ari', 1, 0, 0, kg: 80)],
      );
      await _train(tester);
      await _tap(tester, 'guided-begin');

      expect(find.byKey(const Key('guided-resume-dialog')), findsOneWidget);
      expect(find.text('Seguir desde lo pendiente'), findsOneWidget);
      expect(find.text('Hacer todo de nuevo'), findsOneWidget);

      await _tap(tester, 'guided-resume');

      expect(_text(tester, 'guided-block-count'), 'Bloque 1 de 4');
      expect(h.sessions.writes, isEmpty);
    });

    testWidgets('with sets done only by an athlete who does not train, it does not ask', (
      tester,
    ) async {
      await _pump(tester, records: [_record('andi', 1, 0, 0, kg: 64)]);
      await _train(tester);
      await _tap(tester, 'guided-begin');

      expect(find.byKey(const Key('guided-resume-dialog')), findsNothing);
      expect(_text(tester, 'guided-block-count'), 'Bloque 1 de 4');
    });

    testWidgets('with nothing recorded it does not ask', (tester) async {
      await _pump(
        tester,
        records: [_record('ari', 1, 0, 0, done: false)],
      );
      await _train(tester);
      await _tap(tester, 'guided-begin');

      expect(find.byKey(const Key('guided-resume-dialog')), findsNothing);
    });

    testWidgets('cancelling the question stays on the athletes', (tester) async {
      await _pump(tester, records: [_record('ari', 1, 0, 0, kg: 80)]);
      await _train(tester);
      await _tap(tester, 'guided-begin');
      await _tap(tester, 'guided-resume-cancel');

      expect(find.text('¿Quiénes entrenan?'), findsOneWidget);
    });
  });

  group('redoing the day (E7.23)', () {
    Future<void> redo(WidgetTester tester) async {
      await _train(tester);
      await _tap(tester, 'guided-athlete-andi');
      await _tap(tester, 'guided-begin');
      await _tap(tester, 'guided-redo');
    }

    testWidgets('starts at block 1, offers every set and shows what was recorded', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        records: [_record('ari', 1, 0, 0, kg: 70, reps: 3)],
      );
      await redo(tester);

      expect(_text(tester, 'guided-block-count'), 'Bloque 1 de 4');
      await _skipBlock(tester);
      await _tap(tester, 'guided-mode-simultaneous');
      await _tap(tester, 'guided-start-block');

      // Both athletes are in the step, though Ari's set was recorded.
      expect(find.byKey(const Key('guided-card-ari')), findsOneWidget);
      expect(find.byKey(const Key('guided-card-andi')), findsOneWidget);
      expect(_text(tester, 'guided-before-ari'), 'antes: 3 × 70 kg');
      expect(find.byKey(const Key('guided-before-andi')), findsNothing);
      // The card starts from the proposal, not from the record.
      expect(_text(tester, 'guided-values-ari'), '80 kg × 5 reps');
      expect(h.sessions.writes, isEmpty);
    });

    testWidgets('finishing a recorded set overwrites it with the new values', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        records: [_record('ari', 1, 0, 0, kg: 70, reps: 3, manualKg: true)],
      );
      await redo(tester);
      await _skipBlock(tester);
      await _tap(tester, 'guided-mode-simultaneous');
      await _tap(tester, 'guided-start-block');
      await _tap(tester, 'guided-step-main');
      await _tap(tester, 'guided-step-main');

      expect(h.sessions.writes.map(_w), ['ari 1-0-0 done', 'andi 1-0-0 done']);
      final ari = h.sessions.writes.first;
      expect(ari.manualKg, isNull); // the old typed kilos are not carried over
      expect(ari.reps, isNull);
      expect(_text(tester, 'guided-set'), 'Serie 2 de 2');
    });

    testWidgets('a set that is not redone keeps its record, nothing is unmarked', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        records: [_record('ari', 1, 0, 0, kg: 80)],
      );
      await redo(tester);
      await _skipBlock(tester);
      await _tap(tester, 'guided-mode-simultaneous');
      await _tap(tester, 'guided-start-block');
      await _tap(tester, 'guided-not-done-ari');
      await _tap(tester, 'guided-step-main');
      await _tap(tester, 'guided-step-main');

      // Only Andi's set was written: Ari's record is untouched and no write has done = false.
      expect(h.sessions.writes.map(_w), ['andi 1-0-0 done']);
      expect(h.sessions.writes.every((w) => w.done), isTrue);
      final live = h.container.read(sessionScreenProvider).live!;
      expect(recordOf(live, 'ari', 1, 0, 0)?.done, isTrue);
    });

    testWidgets('a day that is done can be entered again and redone, block included', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        records: [
          for (final a in ['ari', 'andi'])
            for (var s = 0; s < 2; s++) _record(a, 1, 0, s, kg: 80),
        ],
      );
      await redo(tester);
      await _skipBlock(tester);
      await _tap(tester, 'guided-start-block');

      // The block is not closed for having everything recorded.
      expect(_text(tester, 'guided-block-name'), 'Principal');
      expect(_text(tester, 'guided-set'), 'Serie 1 de 2 · turno de Ari');
      await _tap(tester, 'guided-step-main');
      await _tap(tester, 'guided-step-main');
      expect(h.sessions.writes.map(_w), ['ari 1-0-0 done']);
    });

    testWidgets('"Seguir" on a done day closes the block that has nothing left', (
      tester,
    ) async {
      await _pump(
        tester,
        records: [
          for (final a in ['ari', 'andi'])
            for (var s = 0; s < 2; s++) _record(a, 1, 0, s, kg: 80),
        ],
      );
      await _train(tester);
      await _tap(tester, 'guided-athlete-andi');
      await _tap(tester, 'guided-begin');
      await _tap(tester, 'guided-resume');
      await _skipBlock(tester);
      await _tap(tester, 'guided-start-block');

      expect(_text(tester, 'guided-block-name'), 'Accesorios');
    });

    testWidgets('without signal the redone sets stay queued and go out when it returns, the last one', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        records: [_record('ari', 1, 0, 0, kg: 80)],
      );
      await _train(tester);
      await _tap(tester, 'guided-begin');
      await _tap(tester, 'guided-redo');
      await _skipBlock(tester);
      await _tap(tester, 'guided-start-block');
      h.sessions.offlineSets = true;
      await _tap(tester, 'guided-step-main');
      await _tap(tester, 'guided-step-main'); // Ari's set, queued
      await tester.pumpAndSettle();

      final queue = h.container.read(setSyncQueueProvider);
      expect(queue.pending.map((p) => _w(p.write)), ['ari 1-0-0 done']);
      expect(h.sessions.writes, isEmpty);

      h.sessions.offlineSets = false;
      await queue.flush();
      await tester.pumpAndSettle();

      expect(queue.pending, isEmpty);
      expect(h.sessions.writes.map(_w), ['ari 1-0-0 done']);
    });
  });

  group('kilos per athlete in a set in kilos (Ari, 2026-11-21)', () {
    final pressDay = _planOf(const [
      PlanBlock(
        name: 'Accesorios',
        categoryId: 'accesorio',
        prescriptions: [
          Prescription(
            exerciseId: 'press',
            sets: [
              PlanSet(reps: 10, byAthlete: {'ari': AthleteSetLoad(kg: 12.5), 'andi': AthleteSetLoad(kg: 16)}),
            ],
          ),
        ],
      ),
    ]);

    /// The server's proposal: the shared rule over the plan, as `kilos-propuestos` computes it.
    List<ProposedSet> proposed(String athleteId) => proposedDaySets(
      blocks: pressDay.weekModels.single.days.single.blocks,
      exercises: {'press': _press},
      athleteId: athleteId,
      on: _today,
      references: const [],
      factors: const [],
      fixedKg: const {},
      equipo: Equipo.estandarDe('c1'),
    );

    testWidgets('the preview and the cards show each athlete\'s kilos', (tester) async {
      _served = pressDay;
      await _pump(tester, sessions: _Sessions()..proposals = proposed);
      await _toBlock(tester, 0);

      expect(_text(tester, 'guided-preview-0-ari'), endsWith('12.5 kg'));
      expect(_text(tester, 'guided-preview-0-andi'), endsWith('16 kg'));

      await _tap(tester, 'guided-mode-simultaneous');
      await _tap(tester, 'guided-start-block');
      expect(_text(tester, 'guided-values-ari'), '12.5 kg × 10 reps');
      expect(_text(tester, 'guided-values-andi'), '16 kg × 10 reps');
    });
  });

  group('kilos typed by hand per athlete in a set by % (Ari, 2026-11-21)', () {
    // Ari's kilos were typed by hand; Andi was left blank and keeps the suggestion frozen when planning.
    final squatDay = _planOf(const [
      PlanBlock(
        name: 'Principal',
        categoryId: 'primario',
        prescriptions: [
          Prescription(
            exerciseId: 'sq',
            sets: [
              PlanSet(
                reps: 5,
                pct: 65,
                byAthlete: {
                  'ari': AthleteSetLoad(pct: 60, kg: 60, manualKg: true),
                  'andi': AthleteSetLoad(pct: 65, kg: 52.5),
                },
              ),
            ],
          ),
        ],
      ),
    ]);

    List<ProposedSet> proposed(String athleteId) => proposedDaySets(
      blocks: squatDay.weekModels.single.days.single.blocks,
      exercises: {'sq': ex('sq', 'Sentadilla')},
      athleteId: athleteId,
      on: _today,
      references: const [],
      factors: const [],
      fixedKg: const {},
      equipo: Equipo.estandarDe('c1'),
    );

    testWidgets('the session proposes the kilos typed by hand, and the suggestion to whoever was left blank', (
      tester,
    ) async {
      _served = squatDay;
      await _pump(tester, sessions: _Sessions()..proposals = proposed);
      await _toBlock(tester, 0);

      expect(_text(tester, 'guided-preview-0-ari'), endsWith('60 kg'));
      expect(_text(tester, 'guided-preview-0-andi'), endsWith('52.5 kg'));
    });
  });

  group('preview', () {
    testWidgets('shows the block, each athlete\'s part and the mode', (
      tester,
    ) async {
      await _pump(tester);
      await _toBlock(tester, 0);

      expect(_text(tester, 'guided-block-count'), 'Bloque 1 de 4');
      expect(_text(tester, 'guided-block-name'), 'Movilidad');
      expect(find.text('Hombros'), findsOneWidget);
      // A block without sets offers no mode.
      expect(find.byKey(const Key('guided-mode-turns')), findsNothing);

      await _skipBlock(tester);

      expect(_text(tester, 'guided-block-count'), 'Bloque 2 de 4');
      expect(_text(tester, 'guided-block-name'), 'Principal');
      final ari = _text(tester, 'guided-preview-0-ari');
      expect(ari, startsWith('Ari: '));
      expect(ari, endsWith('80 kg'));
      expect(_text(tester, 'guided-preview-0-andi'), endsWith('64 kg'));
      expect(_chosen(tester, 'guided-mode-turns'), true);
      expect(_chosen(tester, 'guided-mode-simultaneous'), false);
    });

    testWidgets('one athlete gets no mode picker', (tester) async {
      await _pump(tester);
      await _train(tester);
      await _tap(tester, 'guided-begin');
      await _skipBlock(tester);

      expect(_text(tester, 'guided-block-name'), 'Principal');
      expect(find.byKey(const Key('guided-mode-turns')), findsNothing);
    });
  });

  group('sequential or circuit (E7.22)', () {
    // A sequential block of two exercises with two sets each.
    final biserie = _planOf(const [
      PlanBlock(
        name: 'Biserie',
        categoryId: 'accesorio',
        prescriptions: [
          Prescription(exerciseId: 'curl', sets: [PlanSet(reps: 10), PlanSet(reps: 10)]),
          Prescription(exerciseId: 'face', sets: [PlanSet(reps: 12), PlanSet(reps: 12)]),
        ],
      ),
    ]);

    /// "Curl 1" style label of the step on screen.
    String where(WidgetTester tester) =>
        '${_text(tester, 'guided-exercise')} ${_text(tester, 'guided-set').split(' ')[1]}';

    Future<void> finish(WidgetTester tester) async {
      await _tap(tester, 'guided-step-main');
      await _tap(tester, 'guided-step-main');
    }

    testWidgets('a sequential block shows the selector, starting sequential', (
      tester,
    ) async {
      _served = biserie;
      await _pump(tester);
      await _train(tester);
      await _tap(tester, 'guided-begin');

      expect(find.text('Orden'), findsOneWidget);
      expect(_chosen(tester, 'guided-order-sequential'), true);
      expect(_chosen(tester, 'guided-order-circuit'), false);
    });

    testWidgets('chosen in the preview, the list alternates A1, B1, A2, B2', (
      tester,
    ) async {
      _served = biserie;
      final h = await _pump(tester);
      await _train(tester);
      await _tap(tester, 'guided-begin');
      await _tap(tester, 'guided-order-circuit');
      expect(_chosen(tester, 'guided-order-circuit'), true);
      await _tap(tester, 'guided-start-block');

      final seen = <String>[];
      for (var i = 0; i < 4; i++) {
        seen.add(where(tester));
        await finish(tester);
      }

      expect(seen, ['Curl 1', 'Face pull 1', 'Curl 2', 'Face pull 2']);
      expect(h.sessions.writes.map(_w), [
        'ari 0-0-0 done',
        'ari 0-1-0 done',
        'ari 0-0-1 done',
        'ari 0-1-1 done',
      ]);
    });

    testWidgets('sequential goes through one exercise and then the other', (
      tester,
    ) async {
      _served = biserie;
      await _pump(tester);
      await _train(tester);
      await _tap(tester, 'guided-begin');
      await _tap(tester, 'guided-start-block');

      final seen = <String>[];
      for (var i = 0; i < 4; i++) {
        seen.add(where(tester));
        await finish(tester);
      }
      expect(seen, ['Curl 1', 'Curl 2', 'Face pull 1', 'Face pull 2']);
    });

    testWidgets('switching to circuit mid-block keeps A1 done and goes on with B1', (
      tester,
    ) async {
      _served = biserie;
      final h = await _pump(tester);
      await _train(tester);
      await _tap(tester, 'guided-begin');
      await _tap(tester, 'guided-start-block');
      await finish(tester); // Curl 1
      expect(where(tester), 'Curl 2');

      await _tap(tester, 'guided-order-circuit');

      expect(where(tester), 'Face pull 1');
      expect(h.sessions.writes.map(_w), ['ari 0-0-0 done']);
      await finish(tester);
      expect(where(tester), 'Curl 2');
    });

    testWidgets('a circuit block of the plan can be done sequentially', (
      tester,
    ) async {
      await _pump(tester);
      await _toBlock(tester, 2);
      expect(_chosen(tester, 'guided-order-circuit'), true);

      await _tap(tester, 'guided-order-sequential');
      await _tap(tester, 'guided-start-block');

      expect(where(tester), 'Curl 1');
      await finish(tester);
      expect(where(tester), 'Curl 2');
    });

    testWidgets('one prescription with sets, or none, shows no selector', (
      tester,
    ) async {
      await _pump(tester);
      await _toBlock(tester, 0); // no sets
      expect(find.byKey(const Key('guided-order-circuit')), findsNothing);
      await _skipBlock(tester);
      expect(_text(tester, 'guided-block-name'), 'Principal'); // one prescription
      expect(find.byKey(const Key('guided-order-circuit')), findsNothing);
      await _tap(tester, 'guided-start-block');
      expect(find.byKey(const Key('guided-order-circuit')), findsNothing);
    });
  });

  group('steps', () {
    testWidgets('by turns: one athlete per step, alternating', (tester) async {
      final h = await _pump(tester);
      await _toBlock(tester, 1);
      await _tap(tester, 'guided-start-block');

      expect(_text(tester, 'guided-exercise'), 'Sentadilla');
      expect(_text(tester, 'guided-set'), 'Serie 1 de 2 · turno de Ari');
      expect(find.byKey(const Key('guided-card-ari')), findsOneWidget);
      expect(find.byKey(const Key('guided-card-andi')), findsNothing);
      expect(_text(tester, 'guided-values-ari'), '80 kg × 5 reps');
      expect(find.text('80 %'), findsOneWidget);
      expect(find.text('Iniciar turno de Ari'), findsOneWidget);
      expect(_text(tester, 'guided-next'), 'Sigue: Sentadilla, serie 1 · Andi');

      await _tap(tester, 'guided-step-main');
      expect(find.text('Terminar turno'), findsOneWidget);
      expect(_text(tester, 'guided-set'), 'Serie 1 de 2 · turno de Ari · en curso');

      await _tap(tester, 'guided-step-main');

      expect(h.sessions.writes.map(_w), ['ari 1-0-0 done']);
      expect(h.sessions.writes.single.manualKg, isNull);
      expect(_text(tester, 'guided-set'), 'Serie 1 de 2 · turno de Andi');
      expect(_text(tester, 'guided-values-andi'), '64 kg × 5 reps');
    });

    testWidgets('simultaneous: every athlete in one step, one write each', (
      tester,
    ) async {
      final h = await _pump(tester);
      await _toBlock(tester, 1);
      await _tap(tester, 'guided-mode-simultaneous');
      await _tap(tester, 'guided-start-block');

      expect(_text(tester, 'guided-set'), 'Serie 1 de 2');
      expect(find.byKey(const Key('guided-card-ari')), findsOneWidget);
      expect(find.byKey(const Key('guided-card-andi')), findsOneWidget);
      expect(_text(tester, 'guided-next'), 'Sigue: Sentadilla, serie 2');

      await _tap(tester, 'guided-step-main');
      expect(find.text('Terminar serie'), findsOneWidget);
      await _tap(tester, 'guided-step-main');

      expect(h.sessions.writes.map(_w), ['ari 1-0-0 done', 'andi 1-0-0 done']);
      expect(_text(tester, 'guided-set'), 'Serie 2 de 2');
      expect(_text(tester, 'guided-next'), 'Es el último paso del bloque.');
    });

    testWidgets('the kilos and reps typed are what is recorded; "No hizo esta serie" records nothing', (
      tester,
    ) async {
      final h = await _pump(tester);
      await _toBlock(tester, 1);
      await _tap(tester, 'guided-mode-simultaneous');
      await _tap(tester, 'guided-start-block');

      await _tap(tester, 'guided-edit-ari');
      await tester.enterText(find.byKey(const Key('session-set-kg')), '85');
      await tester.enterText(find.byKey(const Key('session-set-reps')), '4');
      await _tap(tester, 'session-set-save');
      expect(_text(tester, 'guided-values-ari'), '85 kg × 4 reps');

      await _tap(tester, 'guided-not-done-andi');
      expect(find.text('No hace esta serie'), findsOneWidget);
      expect(find.text('Contar esta serie'), findsOneWidget);

      await _tap(tester, 'guided-step-main');
      await _tap(tester, 'guided-step-main');

      final write = h.sessions.writes.single;
      expect(_w(write), 'ari 1-0-0 done');
      expect(write.manualKg, 85);
      expect(write.reps, 4);
      // Andi's first set is not offered again.
      expect(_text(tester, 'guided-set'), 'Serie 2 de 2');
    });

    testWidgets('leaving the exercise drops that athlete from it', (
      tester,
    ) async {
      final h = await _pump(tester);
      await _toBlock(tester, 1);
      await _tap(tester, 'guided-start-block');

      await _tap(tester, 'guided-leave-ari');

      expect(_text(tester, 'guided-set'), 'Serie 1 de 2 · turno de Andi');
      expect(_text(tester, 'guided-next'), 'Sigue: Sentadilla, serie 2 · Andi');
      await _tap(tester, 'guided-step-main');
      await _tap(tester, 'guided-step-main');
      expect(h.sessions.writes.map(_w), ['andi 1-0-0 done']);
      expect(_text(tester, 'guided-next'), 'Es el último paso del bloque.');
    });

    testWidgets('skipping the exercise goes to the next one', (tester) async {
      final h = await _pump(tester);
      await _toBlock(tester, 2);
      await _tap(tester, 'guided-start-block');
      expect(_text(tester, 'guided-exercise'), 'Curl');

      await _tap(tester, 'guided-more-actions');
      await _tap(tester, 'guided-skip-exercise');

      expect(_text(tester, 'guided-exercise'), 'Face pull');
      expect(_text(tester, 'guided-set'), 'Serie 1 de 1');
      expect(h.sessions.writes, isEmpty);
    });

    testWidgets('switching to simultaneous mid-block groups only what is left', (
      tester,
    ) async {
      final h = await _pump(tester);
      await _toBlock(tester, 1);
      await _tap(tester, 'guided-start-block');
      await _tap(tester, 'guided-step-main');
      await _tap(tester, 'guided-step-main'); // Ari's set 1

      await _tap(tester, 'guided-mode-simultaneous');

      expect(_text(tester, 'guided-set'), 'Serie 1 de 2');
      expect(find.byKey(const Key('guided-card-ari')), findsNothing);
      expect(find.byKey(const Key('guided-card-andi')), findsOneWidget);
      expect(_text(tester, 'guided-next'), 'Sigue: Sentadilla, serie 2');
      await _tap(tester, 'guided-step-main');
      await _tap(tester, 'guided-step-main');
      expect(find.byKey(const Key('guided-card-ari')), findsOneWidget);
      expect(find.byKey(const Key('guided-card-andi')), findsOneWidget);
      expect(h.sessions.writes.map(_w), ['ari 1-0-0 done', 'andi 1-0-0 done']);
    });

    testWidgets('a step already recorded for its athletes is skipped', (
      tester,
    ) async {
      await _pump(
        tester,
        records: [
          _record('ari', 1, 0, 0, kg: 80),
          _record('andi', 1, 0, 0, kg: 64),
          _record('ari', 1, 0, 1, done: false),
        ],
      );
      await _toBlock(tester, 1);
      await _tap(tester, 'guided-start-block');

      expect(_text(tester, 'guided-set'), 'Serie 2 de 2 · turno de Ari');
    });

    testWidgets('the last step closes the block', (tester) async {
      final h = await _pump(tester);
      await _toBlock(tester, 2);
      await _tap(tester, 'guided-start-block');
      for (var i = 0; i < 3; i++) {
        await _tap(tester, 'guided-step-main');
        await _tap(tester, 'guided-step-main');
      }

      expect(h.sessions.writes, hasLength(6));
      expect(_text(tester, 'guided-block-name'), 'Cindy');
    });

    testWidgets('the rest starts the prescription\'s timer, by hand', (
      tester,
    ) async {
      final h = await _pump(tester);
      await _toBlock(tester, 1);
      await _tap(tester, 'guided-start-block');
      await _tap(tester, 'guided-step-main');
      await _tap(tester, 'guided-step-main');
      // Finishing a set starts nothing.
      expect(h.container.read(cronoControllerProvider), isNull);

      final rest = find.byKey(const Key('guided-rest'));
      await tester.ensureVisible(rest);
      await tester.tap(rest);
      await tester.pump();

      expect(
        h.container.read(cronoControllerProvider)?.crono.temporizador.id,
        'rest90',
      );
      // Its ticks outlive the widget tree.
      h.container.read(cronoControllerProvider.notifier).detener();
    });

    testWidgets('without a timer of its own, the rest opens the picker', (
      tester,
    ) async {
      await _pump(tester);
      await _toBlock(tester, 2);
      await _tap(tester, 'guided-start-block');

      await _tap(tester, 'guided-rest');

      expect(find.text('Descanso 90'), findsOneWidget);
    });
  });

  group('blocks', () {
    testWidgets('skip block lives in "Más acciones" of the preview', (
      tester,
    ) async {
      await _pump(tester);
      await _toBlock(tester, 0);
      expect(find.byKey(const Key('guided-skip-block')), findsNothing);
      expect(find.byKey(const Key('guided-start-block')), findsOneWidget);

      await _tap(tester, 'guided-more-actions');

      expect(find.text('Saltar bloque'), findsOneWidget);
    });

    testWidgets('skip and interrupt live in "Más acciones", not on the step', (
      tester,
    ) async {
      await _pump(tester);
      await _toBlock(tester, 1);
      await _tap(tester, 'guided-start-block');

      expect(find.byKey(const Key('guided-skip-exercise')), findsNothing);
      expect(find.byKey(const Key('guided-interrupt')), findsNothing);

      await _tap(tester, 'guided-more-actions');

      expect(find.text('Saltar este ejercicio'), findsOneWidget);
      expect(find.text('Interrumpir bloque'), findsOneWidget);
    });

    testWidgets('interrupting asks first, records nothing and goes on', (
      tester,
    ) async {
      final h = await _pump(tester);
      await _toBlock(tester, 1);
      await _tap(tester, 'guided-start-block');

      await _tap(tester, 'guided-more-actions');
      await _tap(tester, 'guided-interrupt');
      expect(find.text('¿Interrumpir el bloque?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(_text(tester, 'guided-block-name'), 'Principal');

      await _tap(tester, 'guided-more-actions');
      await _tap(tester, 'guided-interrupt');
      await tester.tap(find.text('Interrumpir'));
      await tester.pumpAndSettle();

      expect(_text(tester, 'guided-block-count'), 'Bloque 3 de 4');
      expect(h.sessions.writes, isEmpty);
    });

    testWidgets('a block without sets is seen whole and finished whole', (
      tester,
    ) async {
      await _pump(tester);
      await _toBlock(tester, 0);
      await _tap(tester, 'guided-start-block');

      expect(find.text('Hombros'), findsOneWidget);
      expect(find.byKey(const Key('guided-step-main')), findsNothing);
      await _tap(tester, 'guided-finish-block');

      expect(_text(tester, 'guided-block-count'), 'Bloque 2 de 4');
    });

    testWidgets('the WoD brings its timer; finishing it records its sets', (
      tester,
    ) async {
      final h = await _pump(tester);
      await _toBlock(tester, 3);
      await _tap(tester, 'guided-start-block');

      expect(find.text('20 min AMRAP'), findsOneWidget);
      expect(find.text('⏱ AMRAP 20'), findsOneWidget);
      await _tap(tester, 'guided-finish-block');

      expect(h.sessions.writes.map(_w), ['ari 3-0-0 done', 'andi 3-0-0 done']);
      expect(find.byKey(const Key('guided-finished')), findsOneWidget);
    });

    testWidgets('the clocks run against the system clock', (tester) async {
      final h = await _pump(tester);
      await _toBlock(tester, 1);
      await _tap(tester, 'guided-start-block');
      expect(_text(tester, 'guided-block-clock'), 'Bloque en curso · 00:00');

      h.now = h.now.add(const Duration(seconds: 75));
      await tester.pump(const Duration(seconds: 1));

      expect(_text(tester, 'guided-block-clock'), 'Bloque en curso · 01:15');
      expect(_text(tester, 'guided-total-clock'), '01:15');

      await _tap(tester, 'guided-more-actions');
      await _tap(tester, 'guided-skip-exercise'); // the block closes
      h.now = h.now.add(const Duration(seconds: 30));
      await _tap(tester, 'guided-start-block');
      await tester.pump(const Duration(seconds: 1));
      expect(_text(tester, 'guided-block-clock'), 'Bloque en curso · 00:00');
      expect(_text(tester, 'guided-total-clock'), '01:45');
    });
  });

  group('summary', () {
    /// Starts the block on screen and does every step it offers, as the plan has them.
    Future<void> doBlockAsPlanned(WidgetTester tester) async {
      await _tap(tester, 'guided-start-block');
      if (find.byKey(const Key('guided-finish-block')).evaluate().isNotEmpty) {
        await _tap(tester, 'guided-finish-block');
        return;
      }
      while (find.byKey(const Key('guided-step-main')).evaluate().isNotEmpty) {
        await _tap(tester, 'guided-step-main');
        await _tap(tester, 'guided-step-main');
      }
    }

    Finder inside(String key, String text) => find.descendant(
      of: find.byKey(Key(key)),
      matching: find.text(text),
    );

    testWidgets('an interrupted block is shown as such, with its time and the differences', (
      tester,
    ) async {
      final h = await _pump(tester);
      await _toBlock(tester, 0);
      await _skipBlock(tester); // Movilidad
      await _tap(tester, 'guided-start-block'); // Principal, by turns
      await _tap(tester, 'guided-step-main');
      await _tap(tester, 'guided-step-main'); // Ari's first set
      h.now = h.now.add(const Duration(seconds: 60));
      await _tap(tester, 'guided-more-actions');
      await _tap(tester, 'guided-interrupt');
      await tester.tap(find.text('Interrumpir'));
      await tester.pumpAndSettle();
      await _skipBlock(tester); // Accesorios
      h.now = h.now.add(const Duration(seconds: 15));
      await _tap(tester, 'guided-start-block'); // Cindy
      h.now = h.now.add(const Duration(seconds: 30));
      await _tap(tester, 'guided-finish-block');

      expect(find.text('Día terminado'), findsOneWidget);
      expect(inside('guided-time-0', 'Movilidad · salteado'), findsOneWidget);
      expect(inside('guided-time-0', '—'), findsOneWidget);
      expect(inside('guided-time-1', 'Principal · interrumpido'), findsOneWidget);
      expect(inside('guided-time-1', '01:00'), findsOneWidget);
      expect(inside('guided-time-2', 'Accesorios · salteado'), findsOneWidget);
      expect(inside('guided-time-3', '00:30'), findsOneWidget);
      expect(inside('guided-time-blocks', '01:30'), findsOneWidget);
      expect(inside('guided-time-total', '01:45'), findsOneWidget);

      expect(find.text('Movilidad: no se hizo'), findsOneWidget);
      expect(find.text('Ari · Sentadilla: 1 de 2 series'), findsOneWidget);
      expect(find.text('Andi · Sentadilla: no lo hizo'), findsOneWidget);
      expect(find.text('Ari · Curl: no lo hizo'), findsOneWidget);
      expect(find.text('Andi · Face pull: no lo hizo'), findsOneWidget);
      expect(find.byKey(const Key('guided-no-differences')), findsNothing);

      // The skipped blocks left no time; the interrupted one says so.
      expect(h.sessions.times.map((t) => t.$2.blockIndex), [1, 3]);
      final interrupted = h.sessions.times.first.$2;
      expect(interrupted.interrupted, isTrue);
      expect(interrupted.blockName, 'Principal');
      expect(interrupted.athleteMode, AthleteMode.turns);
      expect(interrupted.athleteIds, ['ari', 'andi']);
      expect(interrupted.end.difference(interrupted.start).inSeconds, 60);
      final whole = h.sessions.times.last.$2;
      expect(whole.interrupted, isFalse);
      expect(whole.athleteMode, isNull);
    });

    testWidgets('a set done with other kilos or reps is compared with the proposal', (
      tester,
    ) async {
      await _pump(tester);
      await _toBlock(tester, 1);
      await _tap(tester, 'guided-mode-simultaneous');
      await _tap(tester, 'guided-start-block');
      await _tap(tester, 'guided-edit-ari');
      await tester.enterText(find.byKey(const Key('session-set-kg')), '77.5');
      await tester.enterText(find.byKey(const Key('session-set-reps')), '4');
      await _tap(tester, 'session-set-save');
      await _tap(tester, 'guided-step-main');
      await _tap(tester, 'guided-step-main');
      await _tap(tester, 'guided-step-main');
      await _tap(tester, 'guided-step-main'); // the second set, as proposed
      await _skipBlock(tester);
      await _skipBlock(tester);

      expect(
        find.text('Ari · Sentadilla, serie 1: 4 × 77.5 kg (plan 5 × 80 kg)'),
        findsOneWidget,
      );
      expect(find.textContaining('Andi · Sentadilla'), findsNothing);
    });

    testWidgets('a day done as planned has no differences', (tester) async {
      final h = await _pump(tester);
      await _toBlock(tester, 0);
      for (var b = 0; b < 4; b++) {
        await doBlockAsPlanned(tester);
      }

      expect(find.text('Día terminado'), findsOneWidget);
      expect(find.text('Se hizo todo según el plan.'), findsOneWidget);
      expect(find.text('Diferencias con el plan'), findsOneWidget);
      expect(h.sessions.times, hasLength(4));
      expect(h.sessions.times.every((t) => !t.$2.interrupted), isTrue);
    });

    testWidgets('Guardar waits for the queue; without signal it offers to retry', (
      tester,
    ) async {
      final h = await _pump(tester);
      h.sessions.offline = true;
      await _toBlock(tester, 0);
      await _skipBlock(tester);
      await _skipBlock(tester);
      await _skipBlock(tester);
      await doBlockAsPlanned(tester);
      expect(find.text('Día terminado'), findsOneWidget);

      await _tap(tester, 'guided-save');

      expect(find.text('Reintentar guardado'), findsOneWidget);
      expect(find.byType(GuidedPage), findsOneWidget);
      expect(h.sessions.times, isEmpty);
      expect(
        h.container.read(setSyncQueueProvider).pendingTimes,
        hasLength(1),
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('guided-save-state'))).data,
        '⚠ sin guardar',
      );

      h.sessions.offline = false;
      await _tap(tester, 'guided-save');

      expect(h.sessions.times, hasLength(1));
      expect(find.byType(GuidedPage), findsNothing);
      expect(find.byKey(const Key('session-train')), findsOneWidget);
    });

    testWidgets('the header says it is saved once the queue is empty', (
      tester,
    ) async {
      await _pump(tester);
      await _toBlock(tester, 1);

      expect(
        tester.widget<Text>(find.byKey(const Key('guided-save-state'))).data,
        '✓ guardado',
      );
    });
  });

  group('leaving', () {
    testWidgets('the last block leads to the end, and back to the session', (
      tester,
    ) async {
      await _pump(tester);
      await _toBlock(tester, 4);

      expect(find.text('Día terminado'), findsOneWidget);
      await _tap(tester, 'guided-save');

      expect(find.byType(GuidedPage), findsNothing);
      expect(find.byKey(const Key('session-train')), findsOneWidget);
    });

    testWidgets('✕ asks first, then goes back to the session', (tester) async {
      await _pump(tester);
      await _toBlock(tester, 1);

      await _tap(tester, 'guided-exit');
      expect(find.text('¿Salir del modo guiado?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.byType(GuidedPage), findsOneWidget);

      await _tap(tester, 'guided-exit');
      await tester.tap(find.text('Salir'));
      await tester.pumpAndSettle();

      expect(find.byType(GuidedPage), findsNothing);
      expect(find.byKey(const Key('session-train')), findsOneWidget);
    });

    testWidgets('entering again resumes the pass where it is, without asking', (
      tester,
    ) async {
      final h = await _pump(tester);
      await _toBlock(tester, 1);
      await _tap(tester, 'guided-mode-simultaneous');
      await _tap(tester, 'guided-start-block');
      await _tap(tester, 'guided-step-main');
      await _tap(tester, 'guided-step-main');
      await _tap(tester, 'guided-exit');
      await tester.tap(find.text('Salir'));
      await tester.pumpAndSettle();

      expect(
        h.sessions.pass!.finished,
        false,
        reason: 'leaving does not finish it for the others',
      );
      await _tap(tester, 'session-train');

      expect(find.text('¿Quiénes entrenan?'), findsNothing);
      expect(find.byKey(const Key('guided-resume-dialog')), findsNothing);
      expect(_text(tester, 'guided-block-name'), 'Principal');
      expect(_text(tester, 'guided-set'), 'Serie 2 de 2');
    });

    testWidgets('a finished pass is not resumed: it chooses who trains again', (
      tester,
    ) async {
      await _pump(tester);
      await _toBlock(tester, 4);
      expect(find.text('Día terminado'), findsOneWidget);
      await _tap(tester, 'guided-save');

      await _tap(tester, 'session-train');

      expect(find.text('¿Quiénes entrenan?'), findsOneWidget);
    });
  });

  group('the shared pass (E7.26)', () {
    /// The pass another device left on block 1 ("Principal", by turns), started at 10:00, with Ari's first set
    /// recorded.
    GuidedPass running() => [
      GuidedPassAction.begin(
        passId: 'other',
        version: 0,
        at: DateTime.utc(2026, 11, 18, 9, 55),
        athleteIds: const ['ari', 'andi'],
        blocks: [
          for (final b in _plan.weekModels.first.days.first.blocks)
            GuidedBlockStart(
              athleteMode: b.athleteMode,
              executionMode: b.executionMode,
            ),
        ],
      ),
      GuidedPassAction.onBlock(
        GuidedActionKind.skipBlock,
        passId: 'other',
        version: 1,
        at: DateTime.utc(2026, 11, 18, 9, 56),
        block: 0,
      ),
      GuidedPassAction.onBlock(
        GuidedActionKind.startBlock,
        passId: 'other',
        version: 2,
        at: DateTime.utc(2026, 11, 18, 10),
        block: 1,
      ),
    ].fold<GuidedPass?>(null, applyGuidedAction)!;

    testWidgets(
      'entering with a pass going on resumes it without asking, on its block, step and clocks',
      (tester) async {
        final h = await _pump(
          tester,
          records: [_record('ari', 1, 0, 0, kg: 80)],
          pass: running(),
        );
        h.now = DateTime.utc(2026, 11, 18, 10, 2, 5);
        await _train(tester);

        expect(find.text('¿Quiénes entrenan?'), findsNothing);
        expect(find.byKey(const Key('guided-resume-dialog')), findsNothing);
        expect(_text(tester, 'guided-block-count'), 'Bloque 2 de 4');
        expect(_text(tester, 'guided-set'), 'Serie 1 de 2 · turno de Andi');
        expect(_text(tester, 'guided-block-clock'), 'Bloque en curso · 02:05');
        expect(_text(tester, 'guided-total-clock'), '02:05');
      },
    );

    testWidgets(
      '"Terminar el día" closes the pass for everyone and shows the summary',
      (tester) async {
        final h = await _pump(tester, pass: running());
        await _train(tester);

        await _tap(tester, 'guided-pass-menu');
        await _tap(tester, 'guided-finish-day');
        expect(find.text('¿Terminar el día?'), findsOneWidget);
        await tester.tap(find.text('Terminar'));
        await tester.pumpAndSettle();

        expect(find.text('Día terminado'), findsOneWidget);
        expect(h.sessions.pass!.finished, true);
        expect(
          h.sessions.pass!.blocks[1].status,
          GuidedBlockStatus.interrupted,
        );
        expect(h.sessions.times.single.$1, 'other-1');
      },
    );

    testWidgets('a new pass can be started over the one going on, or left', (
      tester,
    ) async {
      final h = await _pump(tester, pass: running());
      await _train(tester);

      await _tap(tester, 'guided-pass-menu');
      await _tap(tester, 'guided-start-over');
      expect(find.text('¿Quiénes entrenan?'), findsOneWidget);
      expect(_chosen(tester, 'guided-athlete-andi'), true);
      await _tap(tester, 'guided-back-to-pass');
      expect(_text(tester, 'guided-block-name'), 'Principal');
      expect(h.sessions.pass!.id, 'other');

      await _tap(tester, 'guided-pass-menu');
      await _tap(tester, 'guided-start-over');
      await _tap(tester, 'guided-begin');

      expect(_text(tester, 'guided-block-count'), 'Bloque 1 de 4');
      expect(h.sessions.pass!.id, isNot('other'));
      expect(h.sessions.pass!.blocks[1].status, GuidedBlockStatus.pending);
    });
  });


  group('the day afterwards', () {
    /// Trains the whole day in the guided mode, Ari alone, finishing every set, and goes back to the session.
    Future<void> trainWholeDay(WidgetTester tester) async {
      await _train(tester);
      await _tap(tester, 'guided-begin');
      while (find.byKey(const Key('guided-finished')).evaluate().isEmpty) {
        if (find.byKey(const Key('guided-start-block')).evaluate().isNotEmpty) {
          await _tap(tester, 'guided-start-block');
        } else if (find.byKey(const Key('guided-step-main')).evaluate().isNotEmpty) {
          await _tap(tester, 'guided-step-main');
        } else {
          await _tap(tester, 'guided-finish-block');
        }
      }
      await _tap(tester, 'guided-save');
    }

    bool marked(WidgetTester tester, String set) =>
        (tester.widget<IconButton>(find.byKey(Key('session-check-$set'))).icon as Icon).icon ==
        Icons.check_circle;

    /// The app opened again, on [today], over the same server.
    Future<_Harness> reopen(WidgetTester tester, _Harness h, DateTime today) async {
      await tester.pumpWidget(const SizedBox.shrink());
      return _pump(tester, sessions: h.sessions, today: today);
    }

    final tomorrow = _today.add(const Duration(days: 1));
    final where = UbicacionEnCiclo.desdeFechas(inicio: _start, fecha: _today);
    final doneToday = [
      DayState(cycle: where.ciclo, week: where.semana, day: 1, status: DayProgressStatus.done, date: _today),
    ];

    testWidgets('the sets finished in the guided mode are marked in the session, also after reopening', (
      tester,
    ) async {
      final h = await _pump(tester);
      await trainWholeDay(tester);

      expect(h.sessions.writes.map(_w), [
        'ari 1-0-0 done',
        'ari 1-0-1 done',
        'ari 2-0-0 done',
        'ari 2-1-0 done',
        'ari 2-0-1 done',
        'ari 3-0-0 done',
      ]);
      expect(marked(tester, '1-0-0'), true);
      expect(marked(tester, '1-0-1'), true);

      _states = doneToday;
      await reopen(tester, h, _today);

      expect(marked(tester, '1-0-0'), true);
      expect(marked(tester, '1-0-1'), true);
    });

    testWidgets('on another date, the day done shows the session it was done in', (tester) async {
      final h = await _pump(tester);
      await trainWholeDay(tester);

      _states = doneToday;
      await reopen(tester, h, tomorrow);

      expect(marked(tester, '1-0-0'), true);
      expect(marked(tester, '1-0-1'), true);
    });

    testWidgets('on another date, writing on that day goes to its session, also for an athlete not present', (
      tester,
    ) async {
      final h = await _pump(tester);
      await trainWholeDay(tester);
      _states = doneToday;
      await reopen(tester, h, tomorrow);

      await _tap(tester, 'session-athlete-andi');
      await _tap(tester, 'session-check-1-0-0');

      expect(h.sessions.opened.last, {'ari', 'andi'});
      expect(h.sessions.date, _today, reason: 'no second session tomorrow');
      expect(h.sessions.writes.map(_w).last, 'andi 1-0-0 done');
      expect(marked(tester, '1-0-0'), true);
    });

    testWidgets('a day still pending is looked up only on today', (tester) async {
      final h = await _pump(tester);
      await trainWholeDay(tester);
      await reopen(tester, h, tomorrow);

      expect(marked(tester, '1-0-0'), false);
    });
  });

  group('going back (Ari, 2026-11-21)', () {
    /// Block 1 ("Principal", by turns) running, with Ari's first set done: Andi's turn is on screen.
    Future<_Harness> afterAriFirst(WidgetTester tester) async {
      final h = await _pump(tester);
      await _toBlock(tester, 1);
      await _tap(tester, 'guided-start-block');
      await _tap(tester, 'guided-step-main');
      await _tap(tester, 'guided-step-main');
      expect(_text(tester, 'guided-set'), 'Serie 1 de 2 · turno de Andi');
      return h;
    }

    testWidgets('on the first step there is nothing behind; "Atrás" is away from the timers and 56 dp', (
      tester,
    ) async {
      await _pump(tester);
      await _toBlock(tester, 1);
      await _tap(tester, 'guided-start-block');

      final back = find.byKey(const Key('guided-back'));
      expect(tester.widget<TextButton>(back).onPressed, isNull);
      final size = tester.getSize(back);
      expect(size.height, greaterThanOrEqualTo(56));
      expect(size.width, greaterThanOrEqualTo(56));
      // Above the exercise, far from "⏱ Descanso", which sits by the main button.
      final backTop = tester.getTopLeft(back).dy;
      expect(backTop, lessThan(tester.getTopLeft(find.byKey(const Key('guided-exercise'))).dy));
      expect(backTop, lessThan(tester.getTopLeft(find.byKey(const Key('guided-rest'))).dy - 100));
    });

    testWidgets('shows the step before with what was recorded, and keeps the draft of the current one', (
      tester,
    ) async {
      final h = await afterAriFirst(tester);
      await _tap(tester, 'guided-edit-andi');
      await tester.enterText(find.byKey(const Key('session-set-kg')), '70');
      await _tap(tester, 'session-set-save');

      await _tap(tester, 'guided-back');

      expect(_text(tester, 'guided-set'), 'Serie 1 de 2 · turno de Ari · ya registrada');
      expect(find.byKey(const Key('guided-card-ari')), findsOneWidget);
      expect(find.byKey(const Key('guided-card-andi')), findsNothing);
      expect(_text(tester, 'guided-values-ari'), '80 kg × 5 reps');
      expect(find.byKey(const Key('guided-reviewing')), findsOneWidget);
      expect(find.byKey(const Key('guided-leave-ari')), findsNothing);
      expect(_text(tester, 'guided-next'), 'Después vuelve al paso actual: Sentadilla, serie 1 · Andi');
      expect(tester.widget<TextButton>(find.byKey(const Key('guided-back'))).onPressed, isNull);
      // Looking is not a change: nothing written, nothing unmarked, the pass does not move.
      expect(h.sessions.writes.map(_w), ['ari 1-0-0 done']);
      final version = h.sessions.pass!.version;

      await _tap(tester, 'guided-to-current');

      expect(_text(tester, 'guided-set'), 'Serie 1 de 2 · turno de Andi');
      expect(_text(tester, 'guided-values-andi'), '70 kg × 5 reps');
      expect(h.sessions.writes, hasLength(1));
      expect(h.sessions.pass!.version, version);
    });

    testWidgets('finishing the step behind again overwrites its set, without unmarking it', (
      tester,
    ) async {
      final h = await afterAriFirst(tester);
      final passed = h.sessions.pass!.blocks[1].passed;
      await _tap(tester, 'guided-back');
      await _tap(tester, 'guided-edit-ari');
      await tester.enterText(find.byKey(const Key('session-set-kg')), '85');
      await tester.enterText(find.byKey(const Key('session-set-reps')), '4');
      await _tap(tester, 'session-set-save');
      expect(find.text('Terminar turno de nuevo'), findsOneWidget);

      await _tap(tester, 'guided-step-main');

      expect(h.sessions.writes.map(_w), ['ari 1-0-0 done', 'ari 1-0-0 done']);
      expect(h.sessions.writes.last.manualKg, 85);
      expect(h.sessions.writes.last.reps, 4);
      expect(h.sessions.writes.every((w) => w.done), isTrue);
      final live = h.container.read(sessionScreenProvider).live!;
      final ari = recordOf(live, 'ari', 1, 0, 0)!;
      expect((ari.done, ari.kg, ari.reps), (true, 85, 4));
      expect(h.sessions.pass!.blocks[1].passed, passed);
      // Back on the step the pass is on.
      expect(_text(tester, 'guided-set'), 'Serie 1 de 2 · turno de Andi');
    });

    testWidgets('it goes back step by step and finishing walks forward again', (tester) async {
      final h = await afterAriFirst(tester);
      await _tap(tester, 'guided-step-main');
      await _tap(tester, 'guided-step-main');
      expect(_text(tester, 'guided-set'), 'Serie 2 de 2 · turno de Ari');

      await _tap(tester, 'guided-back');
      expect(_text(tester, 'guided-set'), 'Serie 1 de 2 · turno de Andi · ya registrada');
      await _tap(tester, 'guided-back');
      expect(_text(tester, 'guided-set'), 'Serie 1 de 2 · turno de Ari · ya registrada');

      await _tap(tester, 'guided-step-main');
      expect(_text(tester, 'guided-set'), 'Serie 1 de 2 · turno de Andi · ya registrada');
      await _tap(tester, 'guided-step-main');
      expect(_text(tester, 'guided-set'), 'Serie 2 de 2 · turno de Ari');
      expect(h.sessions.writes.map(_w), [
        'ari 1-0-0 done',
        'andi 1-0-0 done',
        'ari 1-0-0 done',
        'andi 1-0-0 done',
      ]);
    });

    testWidgets('an athlete who did not do the set behind stays without it unless counted', (
      tester,
    ) async {
      final h = await _pump(tester);
      await _toBlock(tester, 1);
      await _tap(tester, 'guided-mode-simultaneous');
      await _tap(tester, 'guided-start-block');
      await _tap(tester, 'guided-not-done-andi');
      await _tap(tester, 'guided-step-main');
      await _tap(tester, 'guided-step-main');
      expect(h.sessions.writes.map(_w), ['ari 1-0-0 done']);

      await _tap(tester, 'guided-back');

      expect(find.text('No hace esta serie'), findsOneWidget);
      await _tap(tester, 'guided-step-main');
      expect(h.sessions.writes.map(_w), ['ari 1-0-0 done', 'ari 1-0-0 done']);

      await _tap(tester, 'guided-back');
      await _tap(tester, 'guided-not-done-andi');
      await _tap(tester, 'guided-step-main');
      expect(h.sessions.writes.map(_w).skip(2), ['ari 1-0-0 done', 'andi 1-0-0 done']);
    });
  });

  group('coming back where it was (Ari, 2026-11-21)', () {
    Future<void> leave(WidgetTester tester) async {
      await _tap(tester, 'guided-exit');
      await tester.tap(find.text('Salir'));
      await tester.pumpAndSettle();
      expect(find.byType(GuidedPage), findsNothing);
    }

    /// Block 1 by turns, Ari's turn started with 85 kg × 4 typed.
    Future<void> typeOnAri(WidgetTester tester) async {
      await _toBlock(tester, 1);
      await _tap(tester, 'guided-start-block');
      await _tap(tester, 'guided-step-main');
      await _tap(tester, 'guided-edit-ari');
      await tester.enterText(find.byKey(const Key('session-set-kg')), '85');
      await tester.enterText(find.byKey(const Key('session-set-reps')), '4');
      await _tap(tester, 'session-set-save');
    }

    testWidgets('leaving and entering again keeps the step started and what was typed', (tester) async {
      final h = await _pump(tester);
      await typeOnAri(tester);
      await leave(tester);

      await _train(tester);

      expect(_text(tester, 'guided-set'), 'Serie 1 de 2 · turno de Ari · en curso');
      expect(_text(tester, 'guided-values-ari'), '85 kg × 4 reps');
      await _tap(tester, 'guided-step-main');
      expect(h.sessions.writes.single.manualKg, 85);
      expect(h.sessions.writes.single.reps, 4);
    });

    testWidgets('a step shown with "Atrás" is shown again on coming back', (tester) async {
      await _pump(tester);
      await _toBlock(tester, 1);
      await _tap(tester, 'guided-start-block');
      await _tap(tester, 'guided-step-main');
      await _tap(tester, 'guided-step-main');
      await _tap(tester, 'guided-back');
      await _tap(tester, 'guided-edit-ari');
      await tester.enterText(find.byKey(const Key('session-set-kg')), '90');
      await _tap(tester, 'session-set-save');
      await leave(tester);

      await _train(tester);

      expect(_text(tester, 'guided-set'), 'Serie 1 de 2 · turno de Ari · ya registrada');
      expect(_text(tester, 'guided-values-ari'), '90 kg × 5 reps');
    });

    testWidgets('after a reload of the app it lands on the same step, from local storage', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final first = await _pump(
        tester,
        positions: SharedPreferencesGuidedPositionStore(),
      );
      await typeOnAri(tester);
      expect(
        (await SharedPreferences.getInstance()).getString(SharedPreferencesGuidedPositionStore.key),
        isNotNull,
      );

      // A new app over the same server and the same local storage.
      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(
        tester,
        sessions: first.sessions,
        positions: SharedPreferencesGuidedPositionStore(),
      );
      await _train(tester);

      expect(_text(tester, 'guided-block-name'), 'Principal');
      expect(_text(tester, 'guided-set'), 'Serie 1 de 2 · turno de Ari · en curso');
      expect(_text(tester, 'guided-values-ari'), '85 kg × 4 reps');
    });

    testWidgets('if the pass moved on meanwhile, what was remembered is dropped', (tester) async {
      final positions = _Positions();
      final h = await _pump(tester, positions: positions);
      await typeOnAri(tester);
      await leave(tester);
      expect(positions.saved?.draft, isNotNull);

      // Another device finished block 1.
      final pass = h.sessions.pass!;
      h.sessions.pass = applyGuidedAction(
        pass,
        GuidedPassAction.onBlock(
          GuidedActionKind.finishBlock,
          passId: pass.id,
          version: pass.version,
          at: h.now,
          block: 1,
        ),
      );
      h.sessions.sessionChanges++;
      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester, sessions: h.sessions, positions: positions);
      await _train(tester);

      expect(_text(tester, 'guided-block-name'), 'Accesorios');
      expect(find.byKey(const Key('guided-start-block')), findsOneWidget);
      expect(positions.saved?.block, 2);
      expect(positions.saved?.draft, isNull);
    });

    testWidgets('a new pass does not take the draft of the one before', (tester) async {
      final positions = _Positions();
      await _pump(tester, positions: positions);
      await typeOnAri(tester);
      final before = positions.saved!.passId;

      await _tap(tester, 'guided-pass-menu');
      await _tap(tester, 'guided-start-over');
      await _tap(tester, 'guided-begin');
      if (find.byKey(const Key('guided-resume')).evaluate().isNotEmpty) {
        await _tap(tester, 'guided-resume');
      }
      await _skipBlock(tester);
      await _tap(tester, 'guided-start-block');

      expect(positions.saved!.passId, isNot(before));
      expect(_text(tester, 'guided-set'), 'Serie 1 de 2 · turno de Ari');
      expect(_text(tester, 'guided-values-ari'), '80 kg × 5 reps');
    });
  });
}
