import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/asignacion/domain/assignment_repository.dart';
import 'package:maktub_frontend/features/asignacion/domain/calendar_repository.dart';
import 'package:maktub_frontend/features/asignacion/presentation/calendar_page.dart';
import 'package:maktub_frontend/features/asignacion/presentation/calendar_providers.dart';
import 'package:maktub_frontend/features/asignacion/presentation/providers.dart';
import 'package:maktub_frontend/features/atletas/presentation/providers.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../catalogo/catalog_admin_fakes.dart';
import '../catalogo/catalog_fakes.dart';
import '../plan/fakes.dart';

class _FakeGroups implements AssignmentRepository {
  @override
  Future<List<AthleteGroup>> groups(String clubId) async => [
    AthleteGroup(id: 'g1', clubId: clubId, name: 'Barra', auditoria: audit()),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeCalendar implements CalendarRepository {
  _FakeCalendar({this.location, this.plan});

  final CalendarLocation? location;
  final PublishedPlanView? plan;
  final dates = <DateTime>[];

  @override
  Future<CalendarLocation?> locate(
    String clubId,
    String groupId,
    DateTime date,
  ) async {
    dates.add(date);
    return location;
  }

  @override
  Future<PublishedPlanView> publishedPlan(String clubId, String planId) async =>
      plan!;
}

CalendarLocation _location({int cycle = 2, int week = 3}) => CalendarLocation(
  assignmentId: 'a1',
  planId: 'p1',
  startDate: DateTime.utc(2026, 9, 1),
  cycle: cycle,
  week: week,
);

PublishedPlanView _plan() => PublishedPlanView(
  id: 'p1',
  name: 'Fuerza',
  type: PlanType.regular,
  publishedAt: DateTime.utc(2026, 11, 1),
  weekAssignment: const ['A', 'A', 'B', 'A'],
  weekModels: const [
    WeekModel(
      id: 'A',
      name: 'Carga',
      days: [
        PlanDay(
          name: 'Lunes',
          blocks: [PlanBlock(name: 'Fuerza A1')],
        ),
        PlanDay(name: 'Martes'),
      ],
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
              note: 'Sin apuro',
              prescriptions: [
                Prescription(
                  exerciseId: 'sq',
                  sets: [
                    PlanSet(reps: 10),
                    PlanSet(reps: 10),
                    PlanSet(reps: 10),
                  ],
                ),
                Prescription(exerciseId: 'st', sets: []),
              ],
            ),
          ],
        ),
        PlanDay(
          name: 'Empuje',
          blocks: [
            PlanBlock(
              name: 'Press',
              prescriptions: [
                Prescription(exerciseId: 'bp', sets: [PlanSet(reps: 5)]),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

Future<GoRouter> _pump(
  WidgetTester tester,
  _FakeCalendar calendar, {
  Set<Rol> roles = const {Rol.coach},
}) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const CalendarPage(assignmentsPath: '/asig'),
      ),
      GoRoute(
        path: '/asig',
        builder: (_, _) => const Scaffold(body: Text('PANTALLA ASIGNACIONES')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...planOverrides(
          FakePlanRepository(),
          roles: roles,
          catalog: FakeCatalogAdminRepository(
            exercisesList: [
              ex('sq', 'Sentadilla'),
              ex('st', 'Estiramiento'),
              ex('bp', 'Press banca'),
            ],
          ),
        ),
        assignmentRepositoryProvider.overrideWithValue(_FakeGroups()),
        calendarRepositoryProvider.overrideWithValue(calendar),
        todayProvider.overrideWithValue(DateTime.utc(2026, 11, 8)),
      ],
      child: MaterialApp.router(
        theme: TemaMaktub.claro(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('opens on the cycle and week of today, on day 1', (tester) async {
    final calendar = _FakeCalendar(location: _location(), plan: _plan());
    await _pump(tester, calendar);

    expect(calendar.dates.single, DateTime.utc(2026, 11, 8));
    expect(find.text('Fuerza · ciclo 2 · semana 3'), findsOneWidget);
    // Week 3 maps to model B; day 1 is its first day.
    expect(find.text('Día 1 · Piernas'), findsOneWidget);
    expect(find.text('Descarga'), findsNWidgets(1));
    expect(find.text('Carga'), findsNWidgets(3));
    expect(find.byKey(const Key('calendar-day-2')), findsOneWidget);
    expect(find.byKey(const Key('calendar-day-3')), findsNothing);
    expect(find.text('Sentadilla'), findsOneWidget);
    expect(find.text('3x10'), findsOneWidget);
    expect(find.text('Sin apuro'), findsOneWidget);
  });

  testWidgets('a prescription without sets shows just the exercise', (
    tester,
  ) async {
    await _pump(tester, _FakeCalendar(location: _location(), plan: _plan()));
    final tile = find.ancestor(
      of: find.text('Estiramiento'),
      matching: find.byType(ListTile),
    );
    expect(tile, findsOneWidget);
    expect(tester.widget<ListTile>(tile).subtitle, isNull);
  });

  testWidgets('choosing another day changes the view', (tester) async {
    await _pump(tester, _FakeCalendar(location: _location(), plan: _plan()));
    await tester.tap(find.byKey(const Key('calendar-day-2')));
    await tester.pumpAndSettle();
    expect(find.text('Día 2 · Empuje'), findsOneWidget);
    expect(find.text('Press banca'), findsOneWidget);
    expect(find.text('Sentadilla'), findsNothing);
  });

  testWidgets('choosing another week goes to its day 1', (tester) async {
    await _pump(tester, _FakeCalendar(location: _location(), plan: _plan()));
    await tester.tap(find.byKey(const Key('calendar-day-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendar-week-1')));
    await tester.pumpAndSettle();
    expect(find.text('Día 1 · Lunes'), findsOneWidget);
    expect(find.text('Fuerza A1'), findsOneWidget);
    // The header keeps telling where today is.
    expect(find.text('Fuerza · ciclo 2 · semana 3'), findsOneWidget);
  });

  testWidgets('no pill shows a done or pending state', (tester) async {
    await _pump(tester, _FakeCalendar(location: _location(), plan: _plan()));
    final pills = find.byType(PildoraMaktub);
    expect(pills, findsNWidgets(6));
    for (final icon in [Icons.check, Icons.check_circle, Icons.circle]) {
      expect(
        find.descendant(of: pills, matching: find.byIcon(icon)),
        findsNothing,
      );
    }
  });

  testWidgets('a coach without an assignment gets a shortcut to Asignaciones', (
    tester,
  ) async {
    await _pump(tester, _FakeCalendar());
    expect(find.text('Todavía no hay un plan asignado'), findsOneWidget);
    await tester.tap(find.byKey(const Key('calendar-go-assignments')));
    await tester.pumpAndSettle();
    expect(find.text('PANTALLA ASIGNACIONES'), findsOneWidget);
  });

  testWidgets('an athlete without an assignment sees only the message', (
    tester,
  ) async {
    await _pump(tester, _FakeCalendar(), roles: {Rol.atleta});
    expect(find.text('Todavía no hay un plan asignado'), findsOneWidget);
    expect(find.byKey(const Key('calendar-go-assignments')), findsNothing);
  });
}
