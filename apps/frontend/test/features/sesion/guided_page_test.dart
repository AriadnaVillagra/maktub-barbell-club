import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:maktub_frontend/features/sesion/domain/block_time_write.dart';
import 'package:maktub_frontend/features/sesion/domain/session_repository.dart';
import 'package:maktub_frontend/features/sesion/domain/set_write.dart';
import 'package:maktub_frontend/features/sesion/presentation/guided_page.dart';
import 'package:maktub_frontend/features/sesion/presentation/providers.dart';
import 'package:maktub_frontend/features/sesion/presentation/session_page.dart';
import 'package:maktub_frontend/features/temporizador/presentation/controllers/crono_controller.dart';
import 'package:maktub_frontend/features/temporizador/presentation/providers.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../access/fakes.dart';
import '../catalogo/catalog_admin_fakes.dart';
import '../catalogo/catalog_fakes.dart';
import '../temporizador/timer_fakes.dart';
import 'draft_fakes.dart';

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
  Future<PublishedPlanView> publishedPlan(String clubId, String planId) async =>
      _served;

  @override
  Future<List<DayState>> dayStates(
    String clubId,
    String groupId,
    DateTime from,
    DateTime to,
  ) async => const [];
}

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
  final opened = <Set<String>>[];
  final writes = <SetWrite>[];

  /// The block times the server took, in order, with their ids.
  final times = <(String, BlockTimeWrite)>[];

  /// Without signal, block times are not taken.
  bool offline = false;

  /// Without signal, sets are not taken either; they stay in the device's queue.
  bool offlineSets = false;

  /// The reps the plan has for each prescription.
  static int _planReps(int block, int prescription) =>
      switch ((block, prescription)) {
        (2, 0) => 10,
        (2, 1) => 12,
        _ => 5,
      };

  static double _kg(String athlete) => athlete == 'ari' ? 80 : 64;

  @override
  Future<LiveSession> open(
    String clubId, {
    required String assignmentId,
    required DateTime date,
    required int week,
    required int day,
    required Set<String> presentAthleteIds,
  }) async {
    opened.add(presentAthleteIds);
    return LiveSession(
      session: Session(
        id: 's1',
        clubId: clubId,
        assignmentId: assignmentId,
        planId: 'p1',
        cycle: 3,
        week: week,
        day: day,
        date: date,
        presentAthleteIds: presentAthleteIds.toList(),
        auditoria: audit(),
      ),
      records: records,
    );
  }

  @override
  Future<List<ProposedSet>> proposedLoads(
    String clubId,
    String sessionId,
    String athleteId,
    AthleteAdjustments adjustments,
  ) async => [
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
    return _record(
      write.athleteId,
      write.blockIndex,
      write.prescriptionIndex,
      write.setIndex,
      done: write.done,
      kg: write.manualKg ?? _kg(write.athleteId),
      reps: write.reps ?? _planReps(write.blockIndex, write.prescriptionIndex),
      manualKg: write.manualKg != null,
    );
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
}) async {
  final h = _Harness(_Sessions(records: records));
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
        meProvider.overrideWith((ref) async => me),
        catalogRepositoryProvider.overrideWithValue(catalog),
        catalogAdminRepositoryProvider.overrideWithValue(catalog),
        assignmentRepositoryProvider.overrideWithValue(_Groups()),
        calendarRepositoryProvider.overrideWithValue(_Calendar()),
        athleteRepositoryProvider.overrideWithValue(_Athletes()),
        sessionRepositoryProvider.overrideWithValue(h.sessions),
        sessionDraftStoreProvider.overrideWithValue(MemoryDraftStore()),
        todayProvider.overrideWithValue(_today),
        timerPlatformProvider.overrideWithValue(h.platform),
        guidedClockProvider.overrideWithValue(() => h.now),
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

/// Opens the session with [present] and enters the guided mode.
Future<void> _train(
  WidgetTester tester, {
  Set<String> present = const {'ari', 'andi'},
}) async {
  for (final id in present.difference({'ari'})) {
    await _tap(tester, 'session-present-$id');
  }
  await _tap(tester, 'session-open');
  await _tap(tester, 'session-train');
}

/// Enters with Ari and Andi and goes to the preview of block [block] (0-based), skipping the ones before.
Future<void> _toBlock(WidgetTester tester, int block) async {
  await _train(tester);
  await _tap(tester, 'guided-athlete-andi');
  await _tap(tester, 'guided-begin');
  if (find.byKey(const Key('guided-resume')).evaluate().isNotEmpty) {
    await _tap(tester, 'guided-resume');
  }
  for (var b = 0; b < block; b++) {
    await _tap(tester, 'guided-skip-block');
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
  setUp(() => _served = _plan);

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

    testWidgets('an athlete who is not present is added to the session', (
      tester,
    ) async {
      final h = await _pump(tester);
      await _train(tester, present: {'ari'});
      await _tap(tester, 'guided-athlete-luz');
      await _tap(tester, 'guided-begin');

      expect(h.sessions.opened.last, {'ari', 'luz'});
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
      await _tap(tester, 'guided-skip-block');
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
      await _tap(tester, 'guided-skip-block');
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
      await _tap(tester, 'guided-skip-block');
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
      await _tap(tester, 'guided-skip-block');
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
      await _tap(tester, 'guided-skip-block');
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
      await _tap(tester, 'guided-skip-block');
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

      await _tap(tester, 'guided-skip-block');

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
      await _tap(tester, 'guided-skip-block');

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
      await _tap(tester, 'guided-skip-block');
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
    testWidgets('interrupting asks first, records nothing and goes on', (
      tester,
    ) async {
      final h = await _pump(tester);
      await _toBlock(tester, 1);
      await _tap(tester, 'guided-start-block');

      await _tap(tester, 'guided-interrupt');
      expect(find.text('¿Interrumpir el bloque?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(_text(tester, 'guided-block-name'), 'Principal');

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
      await _tap(tester, 'guided-skip-block'); // Movilidad
      await _tap(tester, 'guided-start-block'); // Principal, by turns
      await _tap(tester, 'guided-step-main');
      await _tap(tester, 'guided-step-main'); // Ari's first set
      h.now = h.now.add(const Duration(seconds: 60));
      await _tap(tester, 'guided-interrupt');
      await tester.tap(find.text('Interrumpir'));
      await tester.pumpAndSettle();
      await _tap(tester, 'guided-skip-block'); // Accesorios
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
      await _tap(tester, 'guided-skip-block');
      await _tap(tester, 'guided-skip-block');

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
      await _tap(tester, 'guided-skip-block');
      await _tap(tester, 'guided-skip-block');
      await _tap(tester, 'guided-skip-block');
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

    testWidgets('entering again starts over: the position is not kept', (
      tester,
    ) async {
      await _pump(tester);
      await _toBlock(tester, 2);
      await _tap(tester, 'guided-exit');
      await tester.tap(find.text('Salir'));
      await tester.pumpAndSettle();

      await _tap(tester, 'session-train');

      expect(find.text('¿Quiénes entrenan?'), findsOneWidget);
    });
  });
}
