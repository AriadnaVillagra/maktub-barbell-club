import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/access/presentation/providers.dart';
import 'package:maktub_frontend/features/asignacion/domain/assignment_repository.dart';
import 'package:maktub_frontend/features/asignacion/domain/calendar_repository.dart';
import 'package:maktub_frontend/features/asignacion/presentation/calendar_providers.dart';
import 'package:maktub_frontend/features/asignacion/presentation/providers.dart';
import 'package:maktub_frontend/features/atletas/domain/athlete_repository.dart';
import 'package:maktub_frontend/features/atletas/presentation/providers.dart';
import 'package:maktub_frontend/features/catalogo/presentation/providers.dart';
import 'package:maktub_frontend/features/sesion/data/shared_preferences_calendar_layout_store.dart';
import 'package:maktub_frontend/features/sesion/domain/athlete_adjustments.dart';
import 'package:maktub_frontend/features/sesion/domain/block_time_write.dart';
import 'package:maktub_frontend/features/sesion/domain/proposed_days.dart';
import 'package:maktub_frontend/features/sesion/domain/session_repository.dart';
import 'package:maktub_frontend/features/sesion/domain/set_write.dart';
import 'package:maktub_frontend/features/sesion/presentation/calendar_boards.dart';
import 'package:maktub_frontend/features/sesion/presentation/providers.dart';
import 'package:maktub_frontend/features/sesion/presentation/session_page.dart';
import 'package:maktub_ui/maktub_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../access/fakes.dart';
import '../catalogo/catalog_admin_fakes.dart';
import '../catalogo/catalog_fakes.dart';
import 'draft_fakes.dart';
import 'live_fakes.dart';

final _today = DateTime.utc(2026, 11, 18);
final _start = DateTime.utc(2026, 9, 1);

class _FakeGroups implements AssignmentRepository {
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

/// Locates dates with the same rule the backend uses.
class _FakeCalendar implements CalendarRepository {
  _FakeCalendar({
    this.hasAssignment = true,
    this.done = const {},
    this.ownPlan = false,
  });

  final bool hasAssignment;

  /// Whether the athlete also has a plan of their own today, Levantamiento from [_today] (E8.8).
  final bool ownPlan;

  /// The 1-based days of the week of the queried date with sets recorded.
  final Set<int> done;

  /// Done days by (week, day) of the cycle of [_today], on top of [done] (those are in today's week).
  final extraDone = <(int, int)>{};
  int stateCalls = 0;

  @override
  Future<CalendarLocation?> locate(
    String clubId,
    String groupId,
    DateTime date,
  ) async {
    if (!hasAssignment) return null;
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
  ) async => [
    ?await locate(clubId, 'g1', date),
    if (ownPlan)
      CalendarLocation(
        assignmentId: 'own',
        planId: 'lev',
        startDate: _today,
        cycle: 1,
        week: 1,
        athleteId: athleteId,
      ),
  ];

  @override
  Future<PublishedPlanView> publishedPlan(String clubId, String planId) async =>
      planId == 'lev' ? _levantamiento : _plan;

  @override
  Future<List<DayState>> dayStates(
    String clubId,
    String groupId,
    DateTime from,
    DateTime to,
  ) async {
    stateCalls++;
    final where = UbicacionEnCiclo.desdeFechas(inicio: _start, fecha: _today);
    return [
      for (final d in done)
        DayState(cycle: where.ciclo, week: where.semana, day: d, done: true),
      for (final (w, d) in extraDone)
        DayState(cycle: where.ciclo, week: w, day: d, done: true),
    ];
  }
}

class _FakeAthletes implements AthleteRepository {
  int calls = 0;

  @override
  Future<List<AthleteSummary>> athletes(String clubId) async {
    calls++;
    return const [
      AthleteSummary(id: 'ari', userId: 'u1', name: 'Ari'),
      AthleteSummary(id: 'andi', userId: 'u2', name: 'Andi'),
      AthleteSummary(id: 'luz', userId: 'u3', name: 'Luz'),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeSessions implements SessionRepository {
  _FakeSessions({this.factor});

  final double? factor;
  final queries = <(String, AthleteAdjustments)>[];
  Set<String>? openedPresent;
  String? openedAssignment;
  int? openedDay;
  int? openedWeek;

  /// Every set of present athletes the screen opened with, in order.
  final openings = <Set<String>>[];
  int finds = 0;

  /// The session stored on the server, which [find] answers for its week and day; null while nobody wrote.
  LiveSession? existing;

  /// A session another device created: week 4, day 1, with [present] and [records].
  void exists({
    Set<String> present = const {'ari'},
    List<SetRecord> records = const [],
  }) => existing = LiveSession(
    session: Session(
      id: 's1',
      clubId: 'c1',
      assignmentId: 'a1',
      planId: 'p1',
      cycle: 3,
      week: 4,
      day: 1,
      date: _today,
      presentAthleteIds: present.toList(),
      auditoria: audit(),
    ),
    records: records,
  );

  @override
  Future<LiveSession?> find(
    String clubId, {
    required String assignmentId,
    required DateTime date,
    required int week,
    required int day,
  }) async {
    finds++;
    final live = existing;
    return live != null &&
            live.session.assignmentId == assignmentId &&
            live.session.week == week &&
            live.session.day == day
        ? live
        : null;
  }

  /// The kilos the server proposes for [athlete], with [adjustments].
  List<ProposedSet> setsFor(String athlete, AthleteAdjustments adjustments) {
    final adjustment = adjustments.effectiveFor('sq');
    return [
      for (var s = 0; s < 2; s++)
        ProposedSet(
          blockIndex: 0,
          prescriptionIndex: 0,
          setIndex: s,
          exerciseId: 'sq',
          kg: _kg(athlete, adjustment),
          appliedPct: pctEfectivo(80, adjustment),
          workFactor: factor,
        ),
    ];
  }

  /// The kilos of `sq` at 80 %, with the rule the server resolves them with: `ari` has an RM of 100, `andi` 80.
  double _kg(String athlete, int adjustment) => pesoPorPorcentaje(
    rm: athlete == 'ari' ? 100 : 80,
    pct: pctEfectivo(80, adjustment),
    equipo: Equipo.estandarDe('c1'),
    workFactor: factor ?? 100,
  )!;

  @override
  Future<LiveSession> open(
    String clubId, {
    required String assignmentId,
    required DateTime date,
    required int week,
    required int day,
    required Set<String> presentAthleteIds,
  }) async {
    openedPresent = presentAthleteIds;
    openedAssignment = assignmentId;
    openedDay = day;
    openedWeek = week;
    openings.add(presentAthleteIds);
    final before = existing;
    final same =
        before != null &&
        before.session.assignmentId == assignmentId &&
        before.session.week == week &&
        before.session.day == day;
    // Like the server: present athletes add up, and what was recorded stays.
    return existing = LiveSession(
      session: Session(
        id: 's1',
        clubId: clubId,
        assignmentId: assignmentId,
        planId: 'p1',
        cycle: 3,
        week: week,
        day: day,
        date: date,
        presentAthleteIds: {
          if (same) ...before.session.presentAthleteIds,
          ...presentAthleteIds,
        }.toList(),
        auditoria: audit(),
      ),
      records: same ? before.records : const [],
    );
  }

  @override
  Future<void> recordBlockTime(
    String clubId,
    String sessionId,
    String timeId,
    BlockTimeWrite write,
  ) async {}

  @override
  Future<List<ProposedSet>> proposedLoads(
    String clubId,
    String sessionId,
    String athleteId,
    AthleteAdjustments adjustments,
  ) async {
    queries.add((athleteId, adjustments));
    return setsFor(athleteId, adjustments);
  }

  final writes = <SetWrite>[];
  final stored = <(String, int, int, int), SetRecord>{};
  String? refuseWith;
  String? savedSessionNote;

  /// Without signal every write fails as the API client reports it.
  bool offline = false;

  /// Stores like the server: one record per set, computed kilos unless typed, and a missing note keeps the old one.
  @override
  Future<SetRecord> recordSet(
    String clubId,
    String sessionId,
    SetWrite write,
  ) async {
    if (refuseWith case final message?) throw ErrorDeApi(message, estado: 422);
    if (offline) throw const ErrorDeApi('No se pudo conectar con el servidor.');
    writes.add(write);
    final key = (
      write.athleteId,
      write.blockIndex,
      write.prescriptionIndex,
      write.setIndex,
    );
    final note = write.note ?? stored[key]?.note;
    return stored[key] = SetRecord(
      id: 'r-$key',
      clubId: clubId,
      sessionId: sessionId,
      athleteId: write.athleteId,
      exerciseId: 'sq',
      exerciseName: 'Sentadilla',
      blockIndex: write.blockIndex,
      prescriptionIndex: write.prescriptionIndex,
      setIndex: write.setIndex,
      target: const PlanSet(reps: 5, pct: 80),
      done: write.done,
      kg: write.manualKg ?? _kg(write.athleteId, write.adjustment),
      reps: write.reps ?? 5,
      manualKg: write.manualKg != null,
      note: note == null || note.isEmpty ? null : note,
      writtenBy: 'u1',
      auditoria: audit(),
    );
  }

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
  ) async {
    savedSessionNote = note;
    return Session(
      id: sessionId,
      clubId: clubId,
      assignmentId: 'a1',
      planId: 'p1',
      cycle: 3,
      week: 4,
      day: 1,
      date: _today,
      presentAthleteIds: const ['ari'],
      note: note,
      auditoria: audit(),
    );
  }
}

/// The proposed kilos by date (E7.14), with the same rule as [_FakeSessions] and the neutral adjustment.
class _FakeProposedDays implements ProposedDaysRepository {
  _FakeProposedDays(this.sessions);

  final _FakeSessions sessions;
  int calls = 0;

  @override
  Future<List<ProposedDate>> proposedDays(
    String clubId,
    String assignmentId,
    DateTime from,
    DateTime to,
  ) async {
    calls++;
    final where = UbicacionEnCiclo.desdeFechas(inicio: _start, fecha: from);
    return [
      ProposedDate(
        date: from,
        cycle: where.ciclo,
        week: where.semana,
        days: {
          for (var d = 1; d <= 3; d++)
            d: {
              for (final a in const ['ari', 'andi', 'luz'])
                a: sessions.setsFor(a, const AthleteAdjustments()),
            },
        },
      ),
    ];
  }
}

// 2026-11-18 is 11 weeks after the start: cycle 3, week 4 (model B).
final _plan = PublishedPlanView(
  id: 'p1',
  name: 'Fuerza',
  type: PlanType.regular,
  publishedAt: DateTime.utc(2026, 11, 1),
  weekAssignment: const ['A', 'A', 'A', 'B'],
  weekModels: const [
    WeekModel(
      id: 'A',
      name: 'Carga',
      days: [PlanDay(name: 'Empuje A')],
    ),
    WeekModel(
      id: 'B',
      name: 'Descarga',
      days: [
        PlanDay(
          name: 'Piernas',
          blocks: [
            PlanBlock(
              name: 'Principal',
              categoryId: 'primario',
              prescriptions: [
                Prescription(
                  exerciseId: 'sq',
                  sets: [PlanSet(reps: 5, pct: 80), PlanSet(reps: 5, pct: 80)],
                ),
              ],
            ),
            PlanBlock(
              name: 'Entrada en calor',
              categoryId: 'calentamiento',
              prescriptions: [
                Prescription(exerciseId: 'sq', sets: [PlanSet(reps: 10)]),
              ],
            ),
          ],
        ),
        PlanDay(name: 'Empuje'),
        PlanDay(name: 'Tirón'),
      ],
    ),
  ],
);

final _levantamiento = PublishedPlanView(
  id: 'lev',
  name: 'Levantamiento',
  type: PlanType.regular,
  publishedAt: DateTime.utc(2026, 11, 1),
  weekAssignment: const ['L', 'L', 'L', 'L'],
  weekModels: const [
    WeekModel(
      id: 'L',
      name: 'Técnica',
      days: [
        PlanDay(
          name: 'Arranque',
          blocks: [
            PlanBlock(
              name: 'Principal',
              categoryId: 'primario',
              prescriptions: [
                Prescription(exerciseId: 'sq', sets: [PlanSet(reps: 3)]),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  _FakeSessions sessions, {
  Set<Rol> roles = const {Rol.coach},
  String? ownAthlete = 'ari',
  _FakeAthletes? athletes,
  _FakeCalendar? calendar,
  MemoryDraftStore? draft,
  FakeLiveServer? live,
  _FakeProposedDays? proposedDays,
  Widget home = const SessionPage(assignmentsPath: '/asig'),
  bool withRouter = false,
  Size size = const Size(900, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final me = meWith([
    (club('c1', 'Gimnasio', TipoClub.club), roles),
  ], athleteIds: ownAthlete == null ? const {} : {'c1': ownAthlete});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        meProvider.overrideWith((ref) async => me),
        catalogRepositoryProvider.overrideWithValue(
          FakeCatalogAdminRepository(exercisesList: [ex('sq', 'Sentadilla')]),
        ),
        assignmentRepositoryProvider.overrideWithValue(_FakeGroups()),
        calendarRepositoryProvider.overrideWithValue(
          calendar ?? _FakeCalendar(),
        ),
        athleteRepositoryProvider.overrideWithValue(
          athletes ?? _FakeAthletes(),
        ),
        sessionRepositoryProvider.overrideWithValue(sessions),
        remoteProposedDaysRepositoryProvider.overrideWithValue(
          proposedDays ?? _FakeProposedDays(sessions),
        ),
        liveChannelProvider.overrideWithValue(
          FakeLiveChannel(live ?? FakeLiveServer()),
        ),
        sessionDraftStoreProvider.overrideWithValue(
          draft ?? MemoryDraftStore(),
        ),
        todayProvider.overrideWithValue(_today),
      ],
      child: withRouter
          ? MaterialApp.router(
              theme: TemaMaktub.para(Brightness.dark, Densidad.entrenamiento),
              routerConfig: GoRouter(
                routes: [
                  GoRoute(path: '/', builder: (_, _) => home),
                  GoRoute(
                    path: '/asig',
                    builder: (_, _) =>
                        const Scaffold(body: Text('PANTALLA ASIGNACIONES')),
                  ),
                ],
              ),
            )
          : MaterialApp(
              theme: TemaMaktub.para(Brightness.dark, Densidad.entrenamiento),
              home: home,
            ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The texts of the athlete tabs, in the order they show.
List<String> _tabs(WidgetTester tester) => [
  for (final tab in tester.widgetList<Tab>(
    find.descendant(
      of: find.byKey(const Key('session-athletes')),
      matching: find.byType(Tab),
    ),
  ))
    tab.text!,
];

String _kg(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the day it opens on (D13)', () {
    testWidgets('shows the cycle and week of the date', (tester) async {
      await _pump(tester, _FakeSessions());

      final where = UbicacionEnCiclo.desdeFechas(inicio: _start, fecha: _today);
      expect(
        find.text('Fuerza · ciclo ${where.ciclo} · semana ${where.semana}'),
        findsOneWidget,
      );
      expect(where, const UbicacionEnCiclo(ciclo: 3, semana: 4));
    });

    testWidgets('with no recorded sets it opens on day 1', (tester) async {
      await _pump(tester, _FakeSessions());

      expect(find.text('Día 1 · Piernas'), findsOneWidget);
    });

    testWidgets('it opens on the first day without recorded sets', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeSessions(),
        calendar: _FakeCalendar(done: {1, 3}),
      );

      expect(find.text('Día 2 · Empuje'), findsOneWidget);
    });

    testWidgets('if every day has recorded sets it opens on day 1', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeSessions(),
        calendar: _FakeCalendar(done: {1, 2, 3}),
      );

      expect(find.text('Día 1 · Piernas'), findsOneWidget);
    });
  });

  testWidgets('the day picker starts closed with a summary and closes after '
      'choosing a day', (tester) async {
    await _pump(tester, _FakeSessions());
    expect(find.byKey(const Key('session-week-1')), findsNothing);
    final summary = find.byKey(const Key('session-day-summary'));
    expect(
      find.descendant(of: summary, matching: find.text('Día 1 · Piernas')),
      findsOneWidget,
    );

    await _openDayPicker(tester);
    await tester.tap(find.byKey(const Key('session-day-3')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('session-week-1')), findsNothing);
    expect(
      find.descendant(of: summary, matching: find.text('Día 3 · Tirón')),
      findsOneWidget,
    );
  });

  testWidgets('choosing another day shows that day', (tester) async {
    await _pump(tester, _FakeSessions());

    await _openDayPicker(tester);
    await tester.tap(find.byKey(const Key('session-day-3')));
    await tester.pumpAndSettle();

    expect(find.text('Día 3 · Tirón'), findsOneWidget);
    expect(find.text('Día 1 · Piernas'), findsNothing);
  });

  testWidgets('choosing another week shows its first day and model', (
    tester,
  ) async {
    await _pump(tester, _FakeSessions(), calendar: _FakeCalendar(done: {1}));

    await _openDayPicker(tester);
    await tester.tap(find.byKey(const Key('session-week-2')));
    await tester.pumpAndSettle();

    expect(find.text('Día 1 · Empuje A'), findsOneWidget);
  });

  group("an athlete's own plan next to the group's (E8.8)", () {
    testWidgets('with one plan there is nothing to choose', (tester) async {
      await _pump(tester, _FakeSessions());
      expect(find.byKey(const Key('session-plans')), findsNothing);
    });

    testWidgets('both show by name; in the own plan the only tab is the '
        'athlete, and marking creates its session with them', (tester) async {
      final sessions = _FakeSessions();
      await _pump(tester, sessions, calendar: _FakeCalendar(ownPlan: true));

      expect(find.byKey(const Key('session-plan-a1')), findsOneWidget);
      expect(find.byKey(const Key('session-plan-own')), findsOneWidget);
      expect(find.text('Plan propio'), findsOneWidget);
      expect(find.text('Grupo Barra'), findsOneWidget);
      // The group's plan comes first.
      expect(find.text('Fuerza · ciclo 3 · semana 4'), findsOneWidget);
      expect(_tabs(tester), ['Ari', 'Andi', 'Luz']);

      await tester.tap(find.byKey(const Key('session-plan-own')));
      await tester.pumpAndSettle();
      expect(find.text('Levantamiento · ciclo 1 · semana 1'), findsOneWidget);
      expect(find.text('Día 1 · Arranque'), findsOneWidget);
      expect(_tabs(tester), ['Ari']);
      expect(sessions.openings, isEmpty);

      await tester.tap(find.byKey(const Key('session-check-0-0-0')));
      await tester.pumpAndSettle();
      expect(sessions.openedAssignment, 'own');
      expect(sessions.openings, [
        {'ari'},
      ]);
      expect((sessions.openedWeek, sessions.openedDay), (1, 1));
      expect(sessions.writes.single.athleteId, 'ari');
    });

    testWidgets("going back to the group's plan shows its day and writes to "
        'its session', (tester) async {
      final sessions = _FakeSessions();
      await _pump(tester, sessions, calendar: _FakeCalendar(ownPlan: true));
      await tester.tap(find.byKey(const Key('session-plan-own')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('session-check-0-0-0')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('session-plan-a1')));
      await tester.pumpAndSettle();
      expect(find.text('Fuerza · ciclo 3 · semana 4'), findsOneWidget);
      expect(_tabs(tester), ['Ari', 'Andi', 'Luz']);
      await tester.tap(find.byKey(const Key('session-athlete-andi')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('session-check-0-0-0')));
      await tester.pumpAndSettle();
      expect(sessions.openedAssignment, 'a1');
      expect(sessions.openings.last, {'andi'});
      expect((sessions.openedWeek, sessions.openedDay), (4, 1));
    });
  });

  group(
    'the athlete tabs and the session born with the first write (E7.27)',
    () {
      Finder marked(String id) => find.descendant(
        of: find.byKey(Key('session-check-$id')),
        matching: find.byIcon(Icons.check_circle),
      );

      testWidgets('there is no "Abrir sesión" nor "Presentes"', (tester) async {
        await _pump(tester, _FakeSessions());

        expect(find.byKey(const Key('session-open')), findsNothing);
        expect(find.text('Abrir sesión'), findsNothing);
        expect(find.text('Presentes'), findsNothing);
      });

      testWidgets('entering without a session opens nothing and shows each '
          "athlete's kilos by date", (tester) async {
        final sessions = _FakeSessions();
        final days = _FakeProposedDays(sessions);
        await _pump(tester, sessions, proposedDays: days);

        expect(sessions.openings, isEmpty);
        expect(sessions.finds, greaterThan(0));
        expect(days.calls, greaterThan(0));
        expect(sessions.queries, isEmpty);
        expect(_kg(tester, 'session-kg-0-0-0'), '80 kg');

        await tester.tap(find.byKey(const Key('session-athlete-andi')));
        await tester.pumpAndSettle();

        final andi = pesoPorPorcentaje(
          rm: 80,
          pct: 80,
          equipo: Equipo.estandarDe('c1'),
        )!;
        expect(_kg(tester, 'session-kg-0-0-0'), '${_format(andi)} kg');
        expect(sessions.openings, isEmpty);
      });

      testWidgets('every athlete of the group in its order, before and after '
          'the session exists, whichever is chosen', (tester) async {
        final sessions = _FakeSessions();
        await _pump(tester, sessions);
        expect(_tabs(tester), ['Ari', 'Andi', 'Luz']);
        expect(
          tester
              .widget<TabBar>(find.byKey(const Key('session-athletes')))
              .controller!
              .index,
          0,
        );

        await tester.tap(find.byKey(const Key('session-athlete-luz')));
        await tester.pumpAndSettle();
        expect(_tabs(tester), ['Ari', 'Andi', 'Luz']);

        await tester.tap(find.byKey(const Key('session-check-0-0-0')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('session-athlete-andi')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('session-check-0-0-0')));
        await tester.pumpAndSettle();

        expect(sessions.existing!.session.presentAthleteIds, ['luz', 'andi']);
        expect(_tabs(tester), ['Ari', 'Andi', 'Luz']);
      });

      testWidgets("marking Andi's first set creates the session with Andi, and "
          'one of Ari then adds Ari without dropping Andi', (tester) async {
        final sessions = _FakeSessions();
        await _pump(tester, sessions);
        await tester.tap(find.byKey(const Key('session-athlete-andi')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('session-check-0-0-0')));
        await tester.pumpAndSettle();

        expect(sessions.openings, [
          {'andi'},
        ]);
        expect((sessions.openedWeek, sessions.openedDay), (4, 1));
        expect(sessions.writes.single.athleteId, 'andi');
        expect(marked('0-0-0'), findsOneWidget);

        await tester.tap(find.byKey(const Key('session-check-0-0-1')));
        await tester.pumpAndSettle();
        expect(sessions.openings, hasLength(1)); // Andi is already present

        await tester.tap(find.byKey(const Key('session-athlete-ari')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('session-check-0-0-0')));
        await tester.pumpAndSettle();

        expect(sessions.openings.last, containsAll(['andi', 'ari']));
        expect(sessions.existing!.session.presentAthleteIds, ['andi', 'ari']);
        expect(sessions.writes.last.athleteId, 'ari');
        expect(marked('0-0-0'), findsOneWidget);
      });

      testWidgets('a coach outside the group starts on its first athlete', (
        tester,
      ) async {
        await _pump(tester, _FakeSessions(), ownAthlete: null);

        expect(
          tester
              .widget<TabBar>(find.byKey(const Key('session-athletes')))
              .controller!
              .index,
          0,
        );
        expect(_tabs(tester).first, 'Ari');
      });

      testWidgets('an athlete cannot list names and still sees labels', (
        tester,
      ) async {
        final athletes = _FakeAthletes();
        await _pump(
          tester,
          _FakeSessions(),
          roles: const {Rol.atleta},
          athletes: athletes,
        );

        expect(athletes.calls, 0);
        expect(_tabs(tester), ['Yo', 'Atleta 2', 'Atleta 3']);
      });

      testWidgets('a session of the day that already exists is taken without '
          'opening it, with its records, and followed live', (tester) async {
        final live = FakeLiveServer();
        final sessions = _FakeSessions()
          ..exists(records: [_doneRecord('ari', 1)]);
        await _pump(tester, sessions, live: live);

        expect(sessions.openings, isEmpty);
        expect(marked('0-0-1'), findsOneWidget);
        expect(live.openConnections, 1);
      });

      testWidgets('a session another device creates while looking is taken at '
          'the next lookup', (tester) async {
        final live = FakeLiveServer();
        final sessions = _FakeSessions();
        await _pump(tester, sessions, live: live);
        expect(marked('0-0-1'), findsNothing);

        sessions.exists(records: [_doneRecord('ari', 1)]);
        await tester.pump(queueRetryInterval);
        await tester.pumpAndSettle();

        expect(marked('0-0-1'), findsOneWidget);
        expect(sessions.openings, isEmpty);
        expect(live.openConnections, 1);
      });

      testWidgets('choosing another day stops following the session and shows '
          'that day, without asking', (tester) async {
        final live = FakeLiveServer();
        final sessions = _FakeSessions()..exists();
        await _pump(tester, sessions, live: live);
        expect(live.openConnections, 1);

        await _openDayPicker(tester);
        await tester.tap(find.byKey(const Key('session-day-2')));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(live.openConnections, 0);
        expect(find.text('Día 2 · Empuje'), findsOneWidget);
        expect(find.byKey(const Key('session-kg-0-0-0')), findsNothing);

        await _openDayPicker(tester);
        await tester.tap(find.byKey(const Key('session-day-1')));
        await tester.pumpAndSettle();
        expect(live.openConnections, 1);
        expect(sessions.openings, isEmpty);
      });
    },
  );

  group('kilos of each set', () {
    final expected = pesoPorPorcentaje(
      rm: 100,
      pct: 80,
      equipo: Equipo.estandarDe('c1'),
    )!;

    testWidgets('shows what the server proposes (E4: RM × %)', (tester) async {
      await _pump(tester, _FakeSessions());

      expect(_kg(tester, 'session-kg-0-0-0'), '${_format(expected)} kg');
      expect(_kg(tester, 'session-kg-0-0-1'), '${_format(expected)} kg');
      expect(_kg(tester, 'session-detail-0-0-0'), '5 reps · 80 %');
    });

    testWidgets('shows the factor when the viewer can see it (E4)', (
      tester,
    ) async {
      await _pump(tester, _FakeSessions(factor: 90));

      final withFactor = pesoPorPorcentaje(
        rm: 100,
        pct: 80,
        equipo: Equipo.estandarDe('c1'),
        workFactor: 90,
      )!;
      expect(_kg(tester, 'session-kg-0-0-0'), '${_format(withFactor)} kg');
      expect(
        _kg(tester, 'session-detail-0-0-0'),
        '5 reps · 80 % · factor 90 %',
      );
    });

    testWidgets('no kilos for a set without a proposal shows a dash', (
      tester,
    ) async {
      await _pump(tester, _FakeNoLoads());

      expect(_kg(tester, 'session-kg-0-0-0'), '—');
    });

    testWidgets('changing athlete shows their kilos', (tester) async {
      final sessions = _FakeSessions()..exists(present: {'ari', 'andi'});
      await _pump(tester, sessions);

      await tester.tap(find.byKey(const Key('session-athlete-andi')));
      await tester.pumpAndSettle();

      expect(sessions.queries.last.$1, 'andi');
      final andi = pesoPorPorcentaje(
        rm: 80,
        pct: 80,
        equipo: Equipo.estandarDe('c1'),
      )!;
      expect(_kg(tester, 'session-kg-0-0-0'), '${_format(andi)} kg');
    });
  });

  group('the day adjustment', () {
    testWidgets('touching it without a session creates the session and shows '
        'the adjusted kilos', (tester) async {
      final sessions = _FakeSessions();
      await _pump(tester, sessions);
      expect(sessions.openings, isEmpty);

      await tester.tap(find.byKey(const Key('session-adjust-session-plus')));
      await tester.pumpAndSettle();

      expect(sessions.openings, [
        {'ari'},
      ]);
      expect(sessions.queries.last.$2.session, 105);
      expect(_kg(tester, 'session-adjust-session-value'), '105 %');
      expect(_kg(tester, 'session-detail-0-0-0'), '5 reps · 84 %');
    });

    testWidgets('the exercise level wins over the session level', (
      tester,
    ) async {
      await _pump(tester, _FakeSessions());

      await tester.tap(find.byKey(const Key('session-adjust-session-plus')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('session-adjust-ex-0-0-minus')));
      await tester.pumpAndSettle();

      expect(_kg(tester, 'session-adjust-ex-0-0-value'), '100 %');
      expect(_kg(tester, 'session-adjust-session-value'), '105 %');
    });

    testWidgets('of one athlete does not affect the others', (tester) async {
      final sessions = _FakeSessions()..exists(present: {'ari', 'andi'});
      await _pump(tester, sessions);

      await tester.tap(find.byKey(const Key('session-adjust-session-plus')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('session-athlete-andi')));
      await tester.pumpAndSettle();

      expect(_kg(tester, 'session-adjust-session-value'), '100 %');
      final andi = sessions.queries.lastWhere((q) => q.$1 == 'andi');
      final ari = sessions.queries.lastWhere((q) => q.$1 == 'ari');
      expect(andi.$2.session, 100);
      expect(ari.$2.session, 105);

      await tester.tap(find.byKey(const Key('session-athlete-ari')));
      await tester.pumpAndSettle();

      expect(_kg(tester, 'session-adjust-session-value'), '105 %');
    });
  });

  group('the blocks', () {
    testWidgets('each one is its own card, before and after the session '
        'exists', (tester) async {
      // The day picker is a card too; the rest are the blocks.
      final blockCards = find.byWidgetPredicate(
        (w) => w is Card && w.key != const Key('session-day-picker'),
      );
      final sessions = _FakeSessions();
      await _pump(tester, sessions);
      expect(blockCards, findsNWidgets(2));

      await tester.tap(find.byKey(const Key('session-check-0-0-0')));
      await tester.pumpAndSettle();

      expect(blockCards, findsNWidgets(2));
      expect(
        find.descendant(
          of: find.byKey(const Key('session-block-1')),
          matching: find.byKey(const Key('session-kg-1-0-0')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a warm-up has no per-exercise adjustment, a primary does', (
      tester,
    ) async {
      await _pump(tester, _FakeSessions());

      expect(
        find.byKey(const Key('session-adjust-ex-0-0-plus')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('session-adjust-ex-1-0-plus')), findsNothing);
    });
  });

  group('marking and editing a set', () {
    Key check(String id) => Key('session-check-$id');
    Finder marked(String id) => find.descendant(
      of: find.byKey(check(id)),
      matching: find.byIcon(Icons.check_circle),
    );

    Future<void> typeSet(
      WidgetTester tester,
      String id, {
      String? kg,
      String? reps,
    }) async {
      await tester.tap(find.byKey(Key('session-edit-$id')));
      await tester.pumpAndSettle();
      if (kg != null) {
        await tester.enterText(find.byKey(const Key('session-set-kg')), kg);
      }
      if (reps != null) {
        await tester.enterText(find.byKey(const Key('session-set-reps')), reps);
      }
      await tester.tap(find.byKey(const Key('session-set-save')));
      await tester.pumpAndSettle();
    }

    Future<void> writeNote(WidgetTester tester, String key, String text) async {
      await tester.ensureVisible(find.byKey(Key('$key-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('$key-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('session-note-field')), text);
      await tester.tap(find.byKey(const Key('session-note-save')));
      await tester.pumpAndSettle();
    }

    testWidgets('marking sends a write of that set only', (tester) async {
      final sessions = _FakeSessions();
      await _pump(tester, sessions);

      await tester.tap(find.byKey(check('0-0-1')));
      await tester.pumpAndSettle();

      final write = sessions.writes.single;
      expect(
        [write.blockIndex, write.prescriptionIndex, write.setIndex],
        [0, 0, 1],
      );
      expect(write.done, isTrue);
      expect(write.manualKg, isNull);
      expect(marked('0-0-1'), findsOneWidget);
      expect(marked('0-0-0'), findsNothing);
    });

    testWidgets(
      'a set the importer estimated says so until the app writes it (E8.7)',
      (tester) async {
        final sessions = _FakeSessions()
          ..exists(
            records: [
              SetRecord(
                id: 'r-est',
                clubId: 'c1',
                sessionId: 's1',
                athleteId: 'ari',
                exerciseId: 'sq',
                exerciseName: 'Sentadilla',
                blockIndex: 0,
                prescriptionIndex: 0,
                setIndex: 0,
                target: const PlanSet(reps: 5, pct: 80),
                kg: 80,
                reps: 5,
                estimated: true,
                writtenBy: 'sistema:importador',
                auditoria: audit(),
              ),
            ],
          );
        await _pump(tester, sessions);

        expect(
          find.byKey(const Key('session-estimated-0-0-0')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('session-estimated-0-0-1')), findsNothing);
        expect(marked('0-0-0'), findsOneWidget);

        await tester.tap(find.byKey(check('0-0-0')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('session-estimated-0-0-0')), findsNothing);
      },
    );

    testWidgets(
      'an estimated set without kilos shows a dash and takes typed kilos, which end the estimate (E8.7)',
      (tester) async {
        final sessions = _FakeNoLoads()
          ..exists(
            records: [
              SetRecord(
                id: 'r-est',
                clubId: 'c1',
                sessionId: 's1',
                athleteId: 'ari',
                exerciseId: 'sq',
                exerciseName: 'Sentadilla',
                blockIndex: 0,
                prescriptionIndex: 0,
                setIndex: 0,
                target: const PlanSet(reps: 5),
                reps: 5,
                estimated: true,
                writtenBy: 'sistema:importador',
                auditoria: audit(),
              ),
            ],
          );
        await _pump(tester, sessions);

        expect(
          find.byKey(const Key('session-estimated-0-0-0')),
          findsOneWidget,
        );
        expect(marked('0-0-0'), findsOneWidget);
        expect(_kg(tester, 'session-kg-0-0-0'), '—');

        await typeSet(tester, '0-0-0', kg: '42,5');

        final write = sessions.writes.single;
        expect(write.toJson()['kilosManual'], isTrue);
        expect(write.manualKg, 42.5);
        expect(write.done, isTrue);
        expect(write.toJson().containsKey('estimada'), isFalse);
        expect(_kg(tester, 'session-kg-0-0-0'), '42.5 kg');
        expect(find.byKey(const Key('session-estimated-0-0-0')), findsNothing);
      },
    );

    testWidgets('marking the same set twice at once leaves one marked record', (
      tester,
    ) async {
      final sessions = _FakeSessions();
      await _pump(tester, sessions);

      await tester.tap(find.byKey(check('0-0-0')));
      await tester.tap(find.byKey(check('0-0-0')));
      await tester.pumpAndSettle();

      expect(sessions.writes.map((w) => w.done), [true, true]);
      expect(sessions.stored, hasLength(1));
      expect(marked('0-0-0'), findsOneWidget);
    });

    testWidgets('tapping a marked set unmarks it', (tester) async {
      final sessions = _FakeSessions();
      await _pump(tester, sessions);

      await tester.tap(find.byKey(check('0-0-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(check('0-0-0')));
      await tester.pumpAndSettle();

      expect(sessions.writes.last.done, isFalse);
      expect(marked('0-0-0'), findsNothing);
    });

    testWidgets('typed kilos travel as manual and accept a comma', (
      tester,
    ) async {
      final sessions = _FakeSessions();
      await _pump(tester, sessions);

      await typeSet(tester, '0-0-0', kg: '72,5', reps: '3');

      final write = sessions.writes.single;
      expect(write.toJson()['kilosManual'], isTrue);
      expect(write.manualKg, 72.5);
      expect(write.reps, 3);
      expect(write.done, isFalse);
      expect(
        tester.widget<Text>(find.byKey(const Key('session-kg-0-0-0'))).data,
        '72.5 kg',
      );
    });

    testWidgets(
      'saving only the reps does not turn the kilos into typed ones',
      (tester) async {
        final sessions = _FakeSessions();
        await _pump(tester, sessions);

        await typeSet(tester, '0-0-0', reps: '3');

        expect(sessions.writes.single.manualKg, isNull);
        expect(sessions.writes.single.reps, 3);
      },
    );

    testWidgets('invalid values stay in the dialog and write nothing', (
      tester,
    ) async {
      final sessions = _FakeSessions();
      await _pump(tester, sessions);

      await typeSet(tester, '0-0-0', kg: 'mucho');

      expect(find.byKey(const Key('session-set-error')), findsOneWidget);
      expect(sessions.writes, isEmpty);
    });

    testWidgets('the day adjustment does not move typed kilos', (tester) async {
      final sessions = _FakeSessions();
      await _pump(tester, sessions);
      await typeSet(tester, '0-0-0', kg: '72.5');

      await tester.tap(find.byKey(const Key('session-adjust-session-plus')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('session-kg-0-0-0'))).data,
        '72.5 kg',
      );
    });

    testWidgets('marking keeps what was typed', (tester) async {
      final sessions = _FakeSessions();
      await _pump(tester, sessions);
      await typeSet(tester, '0-0-0', kg: '72.5', reps: '3');

      await tester.tap(find.byKey(check('0-0-0')));
      await tester.pumpAndSettle();

      final write = sessions.writes.last;
      expect([write.done, write.manualKg, write.reps], [true, 72.5, 3]);
    });

    testWidgets('a refused write shows the backend error', (tester) async {
      final sessions = _FakeSessions()..refuseWith = 'Ese atleta no está.';
      await _pump(tester, sessions);

      await tester.tap(find.byKey(check('0-0-0')));
      await tester.pumpAndSettle();

      expect(find.text('Ese atleta no está.'), findsOneWidget);
      expect(marked('0-0-0'), findsNothing);
    });

    testWidgets('without signal the mark shows, stays queued and goes later', (
      tester,
    ) async {
      final sessions = _FakeSessions()..offline = true;
      final draft = MemoryDraftStore();
      await _pump(tester, sessions, draft: draft);

      await tester.tap(find.byKey(check('0-0-0')));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      expect(marked('0-0-0'), findsOneWidget);
      expect(_kg(tester, 'session-kg-0-0-0'), '80 kg');
      expect(sessions.writes, isEmpty);
      expect((await draft.load()).queue.single.write.done, isTrue);

      sessions.offline = false;
      await tester.pump(queueRetryInterval);
      await tester.pumpAndSettle();

      expect(sessions.writes.single.done, isTrue);
      expect((await draft.load()).queue, isEmpty);
      expect(marked('0-0-0'), findsOneWidget);
    });

    testWidgets('a set marked on another phone shows at once', (tester) async {
      final live = FakeLiveServer();
      await _pump(tester, _FakeSessions()..exists(), live: live);
      expect(find.byKey(const Key('session-live-connecting')), findsNothing);

      live.write(
        SetWrite.of(
          null,
          athleteId: 'ari',
          blockIndex: 0,
          prescriptionIndex: 0,
          setIndex: 1,
          adjustment: 0,
        ).markedDone(),
      );
      await tester.pumpAndSettle();

      expect(marked('0-0-1'), findsOneWidget);
      expect(marked('0-0-0'), findsNothing);
    });

    testWidgets(
      'while the live channel does not answer, it shows it is connecting and marking still works',
      (tester) async {
        final sessions = _FakeSessions()..exists();
        await _pump(tester, sessions, live: FakeLiveServer()..hanging = true);

        expect(
          find.byKey(const Key('session-live-connecting')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(check('0-0-0')));
        await tester.pumpAndSettle();

        expect(sessions.writes.single.done, isTrue);
        expect(marked('0-0-0'), findsOneWidget);
      },
    );

    testWidgets('reopening shows a mark that was still queued', (tester) async {
      final draft = MemoryDraftStore();
      final offline = _FakeSessions()..offline = true;
      await _pump(tester, offline, draft: draft);
      await tester.tap(find.byKey(check('0-0-1')));
      await tester.pumpAndSettle();

      // A reload: a new app over the same storage, still without signal for writes. The session exists: the mark
      // opened it.
      await tester.pumpWidget(const SizedBox());
      await _pump(
        tester,
        _FakeSessions()
          ..offline = true
          ..existing = offline.existing,
        draft: MemoryDraftStore(draft.disk),
      );

      expect(marked('0-0-1'), findsOneWidget);
      expect(marked('0-0-0'), findsNothing);
    });

    testWidgets('going back to the plan undoes the edits and keeps the marks', (
      tester,
    ) async {
      final sessions = _FakeSessions();
      await _pump(tester, sessions);
      const restore = Key('session-restore-0-0');
      expect(find.byKey(restore), findsNothing);

      await tester.tap(find.byKey(check('0-0-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(restore), findsNothing);

      await typeSet(tester, '0-0-0', kg: '72.5');
      await tester.tap(find.byKey(check('0-0-0')));
      await tester.pumpAndSettle();
      sessions.writes.clear();

      await tester.ensureVisible(find.byKey(restore));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(restore));
      await tester.pumpAndSettle();

      final write = sessions.writes.single;
      expect(write.setIndex, 0);
      expect(write.manualKg, isNull);
      expect(write.done, isTrue);
      expect(marked('0-0-0'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('session-kg-0-0-0'))).data,
        '80 kg',
      );
      expect(find.byKey(restore), findsNothing);
    });

    testWidgets(
      'the exercise note goes on its first set and survives marking',
      (tester) async {
        final sessions = _FakeSessions();
        await _pump(tester, sessions);

        await writeNote(tester, 'session-note-0-0', 'Liviano');

        final write = sessions.writes.single;
        expect([write.setIndex, write.note, write.done], [0, 'Liviano', false]);
        expect(find.byKey(const Key('session-note-0-0-text')), findsOneWidget);
        expect(marked('0-0-0'), findsNothing);

        await tester.ensureVisible(find.byKey(check('0-0-0')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(check('0-0-0')));
        await tester.pumpAndSettle();

        expect(sessions.writes.last.note, isNull);
        expect(find.text('Liviano'), findsOneWidget);
      },
    );

    testWidgets('the session note is saved and shown', (tester) async {
      final sessions = _FakeSessions();
      await _pump(tester, sessions);

      await writeNote(tester, 'session-note-day', 'Buen día');

      expect(sessions.savedSessionNote, 'Buen día');
      expect(find.byKey(const Key('session-note-day-text')), findsOneWidget);
      expect(sessions.writes, isEmpty);
    });
  });

  testWidgets('the backend error when the first write opens is shown', (
    tester,
  ) async {
    await _pump(tester, _FakeOpenFails());

    await tester.tap(find.byKey(const Key('session-check-0-0-0')));
    await tester.pumpAndSettle();

    expect(find.text('La asignación no está activa.'), findsOneWidget);
  });

  testWidgets('without an assignment it says so', (tester) async {
    await _pump(
      tester,
      _FakeSessions(),
      calendar: _FakeCalendar(hasAssignment: false),
    );

    expect(find.byKey(const Key('session-empty')), findsOneWidget);
  });

  group('no assignment', () {
    testWidgets('a coach gets the button to assign and it navigates', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeSessions(),
        calendar: _FakeCalendar(hasAssignment: false),
        withRouter: true,
      );
      await tester.tap(find.byKey(const Key('session-go-assignments')));
      await tester.pumpAndSettle();
      expect(find.text('PANTALLA ASIGNACIONES'), findsOneWidget);
    });

    testWidgets('an athlete sees only the message, in both views', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeSessions(),
        roles: {Rol.atleta},
        calendar: _FakeCalendar(hasAssignment: false),
      );
      expect(find.byKey(const Key('session-empty')), findsOneWidget);
      expect(find.byKey(const Key('session-go-assignments')), findsNothing);
      await tester.tap(find.text('Calendario'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('session-empty')), findsOneWidget);
    });
  });

  group('views and day states', () {
    Finder detail(String key, String text) =>
        find.descendant(of: find.byKey(Key(key)), matching: find.text(text));

    testWidgets('opens on the session view; the selector switches views', (
      tester,
    ) async {
      await _pump(tester, _FakeSessions());
      expect(find.byKey(const Key('session-athletes')), findsOneWidget);
      expect(find.byKey(const Key('calendar-plan')), findsNothing);

      await tester.tap(find.text('Calendario'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar-plan')), findsOneWidget);
      expect(find.byKey(const Key('session-athletes')), findsNothing);

      await tester.tap(find.text('Sesión del día'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('session-athletes')), findsOneWidget);
    });

    testWidgets('can open on the calendar view', (tester) async {
      await _pump(
        tester,
        _FakeSessions(),
        home: const SessionPage(initialView: SessionView.calendar),
      );
      expect(find.byKey(const Key('calendar-plan')), findsOneWidget);
    });

    testWidgets('day pills say done or pending', (tester) async {
      await _pump(tester, _FakeSessions(), calendar: _FakeCalendar(done: {1}));
      await _openDayPicker(tester);
      expect(detail('session-day-1', 'Hecho'), findsOneWidget);
      expect(detail('session-day-2', 'Pendiente'), findsOneWidget);
    });

    testWidgets('the calendar shows every week with its days done or pending', (
      tester,
    ) async {
      final calendar = _FakeCalendar(done: {1});
      calendar.extraDone.add((1, 1));
      await _pump(tester, _FakeSessions(), calendar: calendar);
      await tester.tap(find.text('Calendario'));
      await tester.pumpAndSettle();

      final where = UbicacionEnCiclo.desdeFechas(inicio: _start, fecha: _today);
      expect(find.text('Fuerza'), findsOneWidget);
      expect(
        find.textContaining('Ciclo ${where.ciclo} · 4 semanas'),
        findsOneWidget,
      );
      for (var w = 1; w <= 4; w++) {
        expect(find.byKey(Key('calendar-week-$w')), findsOneWidget);
      }
      expect(detail('calendar-week-1', 'Carga'), findsOneWidget);
      expect(
        detail('calendar-week-${where.semana}', 'Descarga'),
        findsOneWidget,
      );
      expect(
        detail('calendar-week-${where.semana}', 'Esta semana'),
        findsOneWidget,
      );
      expect(find.text('Esta semana'), findsOneWidget);
      expect(detail('calendar-day-${where.semana}-1', 'Hecho'), findsOneWidget);
      expect(
        detail('calendar-day-${where.semana}-2', 'Pendiente'),
        findsOneWidget,
      );
      expect(detail('calendar-day-1-1', 'Hecho'), findsOneWidget);
    });

    testWidgets('recording a set turns the day pill to done', (tester) async {
      final calendar = _FakeCalendar();
      await _pump(tester, _FakeSessions(), calendar: calendar);
      await _openDayPicker(tester);
      expect(detail('session-day-1', 'Pendiente'), findsOneWidget);

      calendar.extraDone.add((
        UbicacionEnCiclo.desdeFechas(inicio: _start, fecha: _today).semana,
        1,
      ));
      await tester.tap(find.byKey(const Key('session-check-0-0-0')));
      await tester.pumpAndSettle();

      await _openDayPicker(tester);
      expect(detail('session-day-1', 'Hecho'), findsOneWidget);
    });
  });

  group('calendar board (E7.25)', () {
    const phone = Size(400, 800);
    const wide = Size(1200, 800);

    Finder inKey(String key, Finder matching) =>
        find.descendant(of: find.byKey(Key(key)), matching: matching);

    Future<void> toCalendar(WidgetTester tester) async {
      await tester.tap(find.text('Calendario'));
      await tester.pumpAndSettle();
    }

    Future<void> choose(WidgetTester tester, String layout) async {
      await tester.tap(inKey('calendar-layout', find.text(layout)));
      await tester.pumpAndSettle();
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    const layouts = {
      'Compacta': CompactBoard,
      'Tarjetas': CardsBoard,
      'Detallada': DetailedBoard,
    };

    testWidgets('the selector switches between the three layouts', (
      tester,
    ) async {
      await _pump(tester, _FakeSessions());
      await toCalendar(tester);
      expect(find.byType(CompactBoard), findsOneWidget);

      for (final MapEntry(key: label, value: type) in layouts.entries) {
        await choose(tester, label);
        for (final other in layouts.values) {
          expect(
            find.byType(other),
            other == type ? findsOneWidget : findsNothing,
          );
        }
      }
    });

    testWidgets('the chosen layout is there when the screen opens again', (
      tester,
    ) async {
      await _pump(tester, _FakeSessions());
      await toCalendar(tester);
      await choose(tester, 'Detallada');
      expect(
        (await SharedPreferences.getInstance()).getString(
          SharedPreferencesCalendarLayoutStore.key,
        ),
        'detailed',
      );

      await tester.pumpWidget(const SizedBox());
      await _pump(
        tester,
        _FakeSessions(),
        home: const SessionPage(initialView: SessionView.calendar),
      );
      expect(find.byType(DetailedBoard), findsOneWidget);
    });

    testWidgets('a layout saved on the device is the one it opens with', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        SharedPreferencesCalendarLayoutStore.key: 'cards',
      });
      await _pump(
        tester,
        _FakeSessions(),
        home: const SessionPage(initialView: SessionView.calendar),
      );
      expect(find.byType(CardsBoard), findsOneWidget);
    });

    for (final label in ['Compacta', 'Tarjetas', 'Detallada']) {
      testWidgets(
        '$label shows each day done or pending and marks the D13 day',
        (tester) async {
          final calendar = _FakeCalendar(done: {1});
          calendar.extraDone.add((1, 1));
          await _pump(tester, _FakeSessions(), calendar: calendar);
          await toCalendar(tester);
          await choose(tester, label);

          // Today is week 4; day 1 is done, so D13 opens day 2.
          expect(inKey('calendar-day-4-1', find.text('Hecho')), findsOneWidget);
          expect(
            inKey('calendar-day-4-2', find.text('Pendiente')),
            findsOneWidget,
          );
          expect(
            inKey('calendar-day-4-3', find.text('Pendiente')),
            findsOneWidget,
          );
          expect(inKey('calendar-day-1-1', find.text('Hecho')), findsOneWidget);
          expect(
            inKey('calendar-day-2-1', find.text('Pendiente')),
            findsOneWidget,
          );
          expect(
            inKey('calendar-day-4-1', find.byIcon(Icons.check_circle)),
            findsOneWidget,
          );
          expect(
            inKey('calendar-day-4-2', find.text('Toca hoy')),
            findsOneWidget,
          );
          expect(find.text('Toca hoy'), findsOneWidget);
          expect(
            tester
                .widget<DayCard>(find.byKey(const Key('calendar-day-4-2')))
                .highlighted,
            isTrue,
          );
          expect(
            inKey('calendar-week-4', find.text('Esta semana')),
            findsOneWidget,
          );
          expect(find.text('Esta semana'), findsOneWidget);
        },
      );
    }

    testWidgets('Compacta shows the main exercises with their sets', (
      tester,
    ) async {
      await _pump(tester, _FakeSessions());
      await toCalendar(tester);

      expect(
        inKey('calendar-day-4-1', find.text('Sentadilla')),
        findsOneWidget,
      );
      expect(
        inKey('calendar-day-4-1', find.text('2x5 al 80 %')),
        findsOneWidget,
      );
      // The warm-up is not a main exercise.
      expect(inKey('calendar-day-4-1', find.text('1x10')), findsNothing);
    });

    testWidgets('Tarjetas shows every block with its exercises', (
      tester,
    ) async {
      await _pump(tester, _FakeSessions());
      await toCalendar(tester);
      await choose(tester, 'Tarjetas');

      for (final text in [
        'Principal',
        'Entrada en calor',
        '2x5 al 80 %',
        '1x10',
      ]) {
        expect(inKey('calendar-day-4-1', find.text(text)), findsOneWidget);
      }
    });

    for (final label in ['Compacta', 'Tarjetas']) {
      testWidgets(
        '$label on a phone: a mouse drags the row sideways and its bar shows',
        (tester) async {
          await _pump(tester, _FakeSessions(), size: const Size(400, 800));
          await toCalendar(tester);
          await choose(tester, label);

          final third = find.byKey(const Key('calendar-day-4-3'));
          await tester.scrollUntilVisible(
            find.byKey(const Key('calendar-week-4')),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          // The third day starts off screen to the right.
          expect(tester.getRect(third).right, greaterThan(400));
          expect(
            find.ancestor(of: third, matching: find.byType(Scrollbar)),
            findsOneWidget,
          );

          final first = find.byKey(const Key('calendar-day-4-1'));
          final before = tester.getRect(first).left;
          final drag = await tester.startGesture(
            tester.getCenter(first),
            kind: PointerDeviceKind.mouse,
          );
          for (var i = 0; i < 10; i++) {
            await drag.moveBy(const Offset(-30, 0));
            await tester.pump();
          }
          await drag.up();
          await tester.pumpAndSettle();
          expect(tester.getRect(first).left, lessThan(before - 100));
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('Detallada shows every day in full with its button', (
      tester,
    ) async {
      await _pump(tester, _FakeSessions());
      await toCalendar(tester);
      await choose(tester, 'Detallada');

      for (final text in [
        'Principal',
        'Entrada en calor',
        '2x5 al 80 %',
        '1x10',
      ]) {
        expect(inKey('calendar-day-4-1', find.text(text)), findsOneWidget);
      }
      for (final (w, d) in [(1, 1), (4, 1), (4, 2), (4, 3)]) {
        expect(find.byKey(Key('calendar-go-$w-$d')), findsOneWidget);
      }
    });

    for (final size in [phone, wide]) {
      testWidgets(
        'in Tarjetas at ${size.width.toInt()} wide, tapping a card opens no panel: '
        'the card gains its button, and a second tap unselects it',
        (tester) async {
          final sessions = _FakeSessions();
          await _pump(tester, sessions, size: size);
          await toCalendar(tester);
          await choose(tester, 'Tarjetas');
          expect(find.byKey(const Key('calendar-go-4-1')), findsNothing);

          await tapKey(tester, 'calendar-day-4-1');

          expect(find.byKey(const Key('calendar-detail')), findsNothing);
          expect(find.byKey(const Key('calendar-detail-hint')), findsNothing);
          expect(
            tester
                .widget<DayCard>(find.byKey(const Key('calendar-day-4-1')))
                .selected,
            isTrue,
          );
          expect(
            inKey('calendar-day-4-1', find.byKey(const Key('calendar-go-4-1'))),
            findsOneWidget,
          );

          await tapKey(tester, 'calendar-day-4-1');
          expect(find.byKey(const Key('calendar-go-4-1')), findsNothing);

          await tapKey(tester, 'calendar-day-2-1');
          await tapKey(tester, 'calendar-go-2-1');
          expect(find.byType(CardsBoard), findsNothing);
          expect(find.text('Día 1 · Empuje A'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );

      for (final label in ['Compacta']) {
        testWidgets(
          'in $label at ${size.width.toInt()} wide, tapping a day opens its detail '
          'without leaving the calendar',
          (tester) async {
            await _pump(tester, _FakeSessions(), size: size);
            await toCalendar(tester);
            await choose(tester, label);
            expect(find.byKey(const Key('calendar-detail')), findsNothing);

            await tapKey(tester, 'calendar-day-4-1');

            expect(find.byType(layouts[label]!), findsOneWidget);
            expect(find.byKey(const Key('session-athletes')), findsNothing);
            expect(
              tester
                  .widget<Text>(find.byKey(const Key('calendar-detail-title')))
                  .data,
              'Semana 4 · Día 1 · Piernas',
            );
            expect(
              inKey('calendar-detail', find.text('Entrada en calor')),
              findsOneWidget,
            );
            expect(
              tester
                  .widget<DayCard>(find.byKey(const Key('calendar-day-4-1')))
                  .selected,
              isTrue,
            );
            final detail = tester.getRect(
              find.byKey(const Key('calendar-detail')),
            );
            if (size == phone) {
              // At the bottom, full width.
              expect(detail.bottom, size.height);
              expect(detail.width, size.width);
            } else {
              // At the side.
              expect(detail.right, size.width);
              expect(detail.width, DayCard.detailWidth);
            }

            await tapKey(tester, 'calendar-day-2-1');
            expect(
              tester
                  .widget<Text>(find.byKey(const Key('calendar-detail-title')))
                  .data,
              'Semana 2 · Día 1 · Empuje A',
            );
            expect(tester.takeException(), isNull);
          },
        );
      }

      testWidgets(
        'at ${size.width.toInt()} wide, "Ir a la sesión de este día" opens that '
        'week and day',
        (tester) async {
          final sessions = _FakeSessions();
          await _pump(tester, sessions, size: size);
          await toCalendar(tester);
          await tapKey(tester, 'calendar-day-2-1');
          await tapKey(tester, 'calendar-go-2-1');

          expect(find.byType(CompactBoard), findsNothing);
          expect(find.text('Día 1 · Empuje A'), findsOneWidget);
          final adjust = find.byKey(const Key('session-adjust-session-plus'));
          await tester.ensureVisible(adjust);
          await tester.tap(adjust);
          await tester.pumpAndSettle();
          expect((sessions.openedWeek, sessions.openedDay), (2, 1));
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'at ${size.width.toInt()} wide, every layout fits without overflow',
        (tester) async {
          await _pump(tester, _FakeSessions(), size: size);
          await toCalendar(tester);
          for (final label in layouts.keys) {
            await choose(tester, label);
            expect(tester.takeException(), isNull, reason: label);
          }
          await choose(tester, 'Compacta');
          await tapKey(tester, 'calendar-day-4-3');
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('in Detallada, the button opens that week and day', (
      tester,
    ) async {
      await _pump(tester, _FakeSessions());
      await toCalendar(tester);
      await choose(tester, 'Detallada');
      await tapKey(tester, 'calendar-go-4-3');

      expect(find.text('Día 3 · Tirón'), findsOneWidget);
      expect(find.byKey(const Key('session-athletes')), findsOneWidget);
    });

    testWidgets('on a phone the detail closes', (tester) async {
      await _pump(tester, _FakeSessions(), size: phone);
      await toCalendar(tester);
      await tapKey(tester, 'calendar-day-4-1');
      await tester.tap(find.byKey(const Key('calendar-detail-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar-detail')), findsNothing);
    });

    testWidgets('on a wide screen, the side panel asks to tap a day', (
      tester,
    ) async {
      await _pump(tester, _FakeSessions(), size: wide);
      await toCalendar(tester);
      expect(find.byKey(const Key('calendar-detail-hint')), findsOneWidget);
    });
  });
}

SetRecord _doneRecord(String athleteId, int setIndex) => SetRecord(
  id: 'r-$athleteId-$setIndex',
  clubId: 'c1',
  sessionId: 's1',
  athleteId: athleteId,
  exerciseId: 'sq',
  exerciseName: 'Sentadilla',
  blockIndex: 0,
  prescriptionIndex: 0,
  setIndex: setIndex,
  target: const PlanSet(reps: 5, pct: 80),
  done: true,
  kg: 80,
  reps: 5,
  writtenBy: 'u1',
  auditoria: audit(),
);

String _format(double kg) =>
    kg == kg.roundToDouble() ? kg.toStringAsFixed(0) : '$kg';

class _FakeNoLoads extends _FakeSessions {
  @override
  List<ProposedSet> setsFor(String athlete, AthleteAdjustments adjustments) =>
      const [
        ProposedSet(
          blockIndex: 0,
          prescriptionIndex: 0,
          setIndex: 0,
          exerciseId: 'sq',
        ),
      ];
}

class _FakeOpenFails extends _FakeSessions {
  @override
  Future<LiveSession> open(
    String clubId, {
    required String assignmentId,
    required DateTime date,
    required int week,
    required int day,
    required Set<String> presentAthleteIds,
  }) async =>
      throw const ErrorDeApi('La asignación no está activa.', estado: 409);
}

/// Opens the week and day pills, which start closed under a one-row summary.
Future<void> _openDayPicker(WidgetTester tester) async {
  if (find.byKey(const Key('session-week-1')).evaluate().isNotEmpty) return;
  await tester.tap(find.byKey(const Key('session-day-picker-toggle')));
  await tester.pumpAndSettle();
}
