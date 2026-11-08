import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:maktub_frontend/features/sesion/domain/athlete_adjustments.dart';
import 'package:maktub_frontend/features/sesion/domain/session_repository.dart';
import 'package:maktub_frontend/features/sesion/presentation/providers.dart';
import 'package:maktub_frontend/features/sesion/presentation/session_page.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../access/fakes.dart';
import '../catalogo/catalog_admin_fakes.dart';
import '../catalogo/catalog_fakes.dart';

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
  _FakeCalendar({this.hasAssignment = true});

  final bool hasAssignment;

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
  Future<PublishedPlanView> publishedPlan(String clubId, String planId) async =>
      _plan;
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
  _FakeSessions({this.done = const {}, this.factor});

  final Set<int> done;
  final double? factor;
  final queries = <(String, AthleteAdjustments)>[];
  Set<String>? openedPresent;
  int? openedDay;
  int? openedWeek;

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
    openedDay = day;
    openedWeek = week;
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
      records: const [],
    );
  }

  @override
  Future<List<ProposedSet>> proposedLoads(
    String clubId,
    String sessionId,
    String athleteId,
    AthleteAdjustments adjustments,
  ) async {
    queries.add((athleteId, adjustments));
    final adjustment = adjustments.effectiveFor('sq');
    return [
      for (var s = 0; s < 2; s++)
        ProposedSet(
          blockIndex: 0,
          prescriptionIndex: 0,
          setIndex: s,
          exerciseId: 'sq',
          kg: _kg(athleteId, adjustment),
          appliedPct: pctEfectivo(80, adjustment),
          workFactor: factor,
        ),
    ];
  }

  @override
  Future<Set<int>> daysWithRecords(
    String clubId,
    String assignmentId, {
    required int cycle,
    required int week,
  }) async => done;
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
              prescriptions: [
                Prescription(
                  exerciseId: 'sq',
                  sets: [PlanSet(reps: 5, pct: 80), PlanSet(reps: 5, pct: 80)],
                ),
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

Future<void> _pump(
  WidgetTester tester,
  _FakeSessions sessions, {
  Set<Rol> roles = const {Rol.coach},
  String? ownAthlete = 'ari',
  _FakeAthletes? athletes,
  _FakeCalendar? calendar,
}) async {
  tester.view.physicalSize = const Size(900, 2400);
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
        todayProvider.overrideWithValue(_today),
      ],
      child: MaterialApp(
        theme: TemaMaktub.para(Brightness.dark, Densidad.entrenamiento),
        home: const SessionPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('session-open')));
  await tester.pumpAndSettle();
}

String _kg(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
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
      await _pump(tester, _FakeSessions(done: {1, 3}));

      expect(find.text('Día 2 · Empuje'), findsOneWidget);
    });

    testWidgets('if every day has recorded sets it opens on day 1', (
      tester,
    ) async {
      await _pump(tester, _FakeSessions(done: {1, 2, 3}));

      expect(find.text('Día 1 · Piernas'), findsOneWidget);
    });
  });

  testWidgets('choosing another day shows that day', (tester) async {
    await _pump(tester, _FakeSessions());

    await tester.tap(find.byKey(const Key('session-day-3')));
    await tester.pumpAndSettle();

    expect(find.text('Día 3 · Tirón'), findsOneWidget);
    expect(find.text('Día 1 · Piernas'), findsNothing);
  });

  testWidgets('choosing another week shows its first day and model', (
    tester,
  ) async {
    await _pump(tester, _FakeSessions(done: {1}));

    await tester.tap(find.byKey(const Key('session-week-2')));
    await tester.pumpAndSettle();

    expect(find.text('Día 1 · Empuje A'), findsOneWidget);
  });

  group('present athletes', () {
    testWidgets('the user starts present and the others can be added', (
      tester,
    ) async {
      final sessions = _FakeSessions();
      await _pump(tester, sessions);

      await tester.tap(find.byKey(const Key('session-present-andi')));
      await tester.pumpAndSettle();
      await _open(tester);

      expect(sessions.openedPresent, {'ari', 'andi'});
      expect(sessions.openedDay, 1);
      expect(sessions.openedWeek, 4);
    });

    testWidgets('without anyone present the session cannot open', (
      tester,
    ) async {
      await _pump(tester, _FakeSessions());

      await tester.tap(find.byKey(const Key('session-present-ari')));
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('session-open')),
      );
      expect(button.onPressed, isNull);
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
      expect(find.text('Yo'), findsOneWidget);
      expect(find.text('Atleta 2'), findsOneWidget);
    });
  });

  group('kilos of each set', () {
    final expected = pesoPorPorcentaje(
      rm: 100,
      pct: 80,
      equipo: Equipo.estandarDe('c1'),
    )!;

    testWidgets('shows what the server proposes (E4: RM × %)', (tester) async {
      await _pump(tester, _FakeSessions());
      await _open(tester);

      expect(_kg(tester, 'session-kg-0-0-0'), '${_format(expected)} kg');
      expect(_kg(tester, 'session-kg-0-0-1'), '${_format(expected)} kg');
      expect(_kg(tester, 'session-detail-0-0-0'), '5 reps · 80 %');
    });

    testWidgets('shows the factor when the viewer can see it (E4)', (
      tester,
    ) async {
      await _pump(tester, _FakeSessions(factor: 90));
      await _open(tester);

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
      await _open(tester);

      expect(_kg(tester, 'session-kg-0-0-0'), '—');
    });

    testWidgets('changing athlete shows their kilos', (tester) async {
      final sessions = _FakeSessions();
      await _pump(tester, sessions);
      await tester.tap(find.byKey(const Key('session-present-andi')));
      await tester.pumpAndSettle();
      await _open(tester);

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
    testWidgets('moves the % of that athlete', (tester) async {
      await _pump(tester, _FakeSessions());
      await _open(tester);

      await tester.tap(find.byKey(const Key('session-adjust-session-plus')));
      await tester.pumpAndSettle();

      expect(_kg(tester, 'session-adjust-session-value'), '105 %');
      expect(_kg(tester, 'session-detail-0-0-0'), '5 reps · 84 %');
    });

    testWidgets('the exercise level wins over the session level', (
      tester,
    ) async {
      await _pump(tester, _FakeSessions());
      await _open(tester);

      await tester.tap(find.byKey(const Key('session-adjust-session-plus')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('session-adjust-ex-0-0-minus')));
      await tester.pumpAndSettle();

      expect(_kg(tester, 'session-adjust-ex-0-0-value'), '100 %');
      expect(_kg(tester, 'session-adjust-session-value'), '105 %');
    });

    testWidgets('of one athlete does not affect the others', (tester) async {
      final sessions = _FakeSessions();
      await _pump(tester, sessions);
      await tester.tap(find.byKey(const Key('session-present-andi')));
      await tester.pumpAndSettle();
      await _open(tester);

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

  testWidgets('choosing another day leaves the open session', (tester) async {
    await _pump(tester, _FakeSessions());
    await _open(tester);

    await tester.tap(find.byKey(const Key('session-day-2')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('session-open')), findsOneWidget);
    expect(find.byKey(const Key('session-kg-0-0-0')), findsNothing);
  });

  testWidgets('the backend error when opening is shown', (tester) async {
    await _pump(tester, _FakeOpenFails());

    await _open(tester);

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
}

String _format(double kg) =>
    kg == kg.roundToDouble() ? kg.toStringAsFixed(0) : '$kg';

class _FakeNoLoads extends _FakeSessions {
  @override
  Future<List<ProposedSet>> proposedLoads(
    String clubId,
    String sessionId,
    String athleteId,
    AthleteAdjustments adjustments,
  ) async => const [
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
