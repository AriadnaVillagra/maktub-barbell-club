import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/asignacion/domain/assignment_repository.dart';
import 'package:maktub_frontend/features/asignacion/presentation/assignments_page.dart';
import 'package:maktub_frontend/features/asignacion/presentation/providers.dart';
import 'package:maktub_frontend/features/atletas/domain/athlete_repository.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../plan/fakes.dart';

final _audit = Auditoria(creadoPor: 'u1', creadoEn: DateTime.utc(2026, 11, 1));

Assignment _assignment(
  String id,
  String planId, {
  AssignmentStatus status = AssignmentStatus.active,
  DateTime? end,
  List<String> athletes = const ['ari', 'andi'],
}) => Assignment(
  id: id,
  clubId: 'c1',
  planId: planId,
  members: [
    for (final a in athletes)
      AssignmentMember(athleteId: a, from: DateTime.utc(2026, 11, 2)),
  ],
  startDate: DateTime.utc(2026, 11, 2),
  status: status,
  endDate: end,
  auditoria: _audit,
);

class FakeAssignmentRepository implements AssignmentRepository {
  FakeAssignmentRepository({List<Assignment> items = const []})
    : items = [...items];

  final List<Assignment> items;
  final calls = <String>[];
  Object? assignFailure;

  @override
  Future<List<AthleteGroup>> groups(String clubId) async => const [];

  @override
  Future<List<Assignment>> assignments(
    String clubId, {
    String? groupId,
  }) async => [...items];

  @override
  Future<Assignment> assign(
    String clubId, {
    required String planId,
    required List<String> athleteIds,
    required DateTime startDate,
  }) async {
    calls.add('assign:$planId:${athleteIds.join(',')}:${aIsoFecha(startDate)}');
    if (assignFailure != null) throw assignFailure!;
    final a = Assignment(
      id: 'a${items.length + 1}',
      clubId: clubId,
      planId: planId,
      members: [
        for (final id in athleteIds)
          AssignmentMember(athleteId: id, from: startDate),
      ],
      startDate: startDate,
      auditoria: _audit,
    );
    items.insert(0, a);
    return a;
  }

  @override
  Future<Assignment> setAthletes(
    String clubId,
    String assignmentId, {
    required List<String> athleteIds,
    required DateTime date,
  }) async {
    calls.add('athletes:$assignmentId:${athleteIds.join(',')}:${aIsoFecha(date)}');
    final i = items.indexWhere((a) => a.id == assignmentId);
    items[i] = items[i].copyWith(
      members: membersAfterChange(
        items[i].members,
        athleteIds: athleteIds,
        date: date,
        startDate: items[i].startDate,
      ),
    );
    return items[i];
  }

  @override
  Future<Assignment> end(
    String clubId,
    String assignmentId, {
    DateTime? endDate,
  }) async {
    calls.add('end:$assignmentId');
    final i = items.indexWhere((a) => a.id == assignmentId);
    items[i] = items[i].copyWith(
      status: AssignmentStatus.ended,
      endDate: DateTime.utc(2026, 11, 8),
    );
    return items[i];
  }
}

const _athletes = [
  AthleteSummary(id: 'ari', userId: 'u1', name: 'Ari'),
  AthleteSummary(id: 'andi', userId: 'u2', name: 'Andi'),
];

Future<void> _pump(
  WidgetTester tester,
  FakeAssignmentRepository repo,
  FakePlanRepository plans, {
  List<AthleteSummary> athletes = _athletes,
}) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...planOverrides(plans, assignments: repo, athletes: athletes),
        assignmentTodayProvider.overrideWithValue(DateTime.utc(2026, 11, 8)),
      ],
      child: MaterialApp(
        theme: TemaMaktub.claro(),
        home: const AssignmentsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

FakePlanRepository _plans() {
  final published = samplePlan(
    id: 'p1',
    name: 'Fuerza',
    models: [model('a', 'A', 2)],
    assignment: ['a'],
  );
  return FakePlanRepository(
    plans: [
      Plan(
        id: 'p1',
        clubId: 'c1',
        name: 'Fuerza',
        type: PlanType.regular,
        weekModels: published.weekModels,
        weekAssignment: published.weekAssignment,
        published: publishedCopyOf(published),
        auditoria: _audit,
      ),
      samplePlan(id: 'p2', name: 'Borrador'),
      samplePlan(
        id: 'p3',
        name: 'Histórico 2025-05',
        type: PlanType.history,
        models: published.weekModels,
        assignment: published.weekAssignment,
        published: publishedCopyOf(published),
      ),
    ],
  );
}

void main() {
  Future<void> openMenu(WidgetTester tester, String id, String item) async {
    await tester.tap(find.byKey(Key('assignment-menu-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('assignment-$item-$id')));
    await tester.pumpAndSettle();
  }

  testWidgets('without athletes it says so and offers no add button', (
    tester,
  ) async {
    await _pump(tester, FakeAssignmentRepository(), _plans(), athletes: []);
    expect(find.byKey(const Key('assignments-no-athletes')), findsOneWidget);
    expect(find.byKey(const Key('assignment-new')), findsNothing);
  });

  testWidgets(
    'assigns a published plan to the athletes chosen, from today by default',
    (tester) async {
      final repo = FakeAssignmentRepository();
      await _pump(tester, repo, _plans());
      expect(find.byKey(const Key('assignment-none-active')), findsOneWidget);
      expect(find.byTooltip('Asignar un plan'), findsOneWidget);

      await tester.tap(find.byKey(const Key('assignment-new')));
      await tester.pumpAndSettle();
      expect(find.text('Inicio: 2026-11-08'), findsOneWidget);
      // Only the published plan is offered.
      await tester.tap(find.byKey(const Key('assign-plan')));
      await tester.pumpAndSettle();
      expect(find.text('Borrador'), findsNothing);
      expect(find.text('Histórico 2025-05'), findsNothing, reason: 'never assigned');
      await tester.tap(find.text('Fuerza').last);
      await tester.pumpAndSettle();
      // Everyone is chosen at first; Andi is left out.
      await tester.tap(find.byKey(const Key('assign-athlete-andi')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('assign-confirm')));
      await tester.pumpAndSettle();

      expect(repo.calls, ['assign:p1:ari:2026-11-08']);
      expect(find.byKey(const Key('assignment-active-a1')), findsOneWidget);
      expect(find.text('Ari\nDesde el 08/11/2026'), findsOneWidget);
      // An athlete with a plan in course can get another one.
      expect(find.byKey(const Key('assignment-new')), findsOneWidget);
    },
  );

  testWidgets('shows the backend error when assigning fails', (tester) async {
    final repo = FakeAssignmentRepository()
      ..assignFailure = const ErrorDeApi(
        'El plan no tiene una versión publicada; publicalo antes de asignarlo.',
        estado: 422,
      );
    await _pump(tester, repo, _plans());
    await tester.tap(find.byKey(const Key('assignment-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assign-confirm')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'El plan no tiene una versión publicada; publicalo antes de asignarlo.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('athletes are added and removed from today, the plan goes on (E6.7)', (
    tester,
  ) async {
    final repo = FakeAssignmentRepository(
      items: [_assignment('a1', 'p1', athletes: ['ari'])],
    );
    await _pump(tester, repo, _plans());
    expect(find.text('Ari\nDesde el 02/11/2026'), findsOneWidget);

    await openMenu(tester, 'a1', 'athletes');
    // Nothing changed yet: nothing to save.
    final save = find.byKey(const Key('assignment-athletes-confirm'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.tap(find.byKey(const Key('assign-athlete-andi')));
    await tester.tap(find.byKey(const Key('assign-athlete-ari')));
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(repo.calls, ['athletes:a1:andi:2026-11-08']);
    expect(find.text('Andi\nDesde el 02/11/2026'), findsOneWidget);
    expect(repo.items.single.status, AssignmentStatus.active);
    expect(repo.items.single.hasAthleteOn('ari', DateTime.utc(2026, 11, 7)), isTrue);
  });

  testWidgets('nobody chosen cannot be saved: that is ending it', (tester) async {
    final repo = FakeAssignmentRepository(
      items: [_assignment('a1', 'p1', athletes: ['ari'])],
    );
    await _pump(tester, repo, _plans());
    await openMenu(tester, 'a1', 'athletes');
    await tester.tap(find.byKey(const Key('assign-athlete-ari')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('assignment-athletes-confirm')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'ending asks first; cancelling keeps it, confirming moves it to Terminadas',
    (tester) async {
      final repo = FakeAssignmentRepository(items: [_assignment('a1', 'p1')]);
      await _pump(tester, repo, _plans());

      await openMenu(tester, 'a1', 'end');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(repo.calls, isEmpty);

      await openMenu(tester, 'a1', 'end');
      await tester.tap(find.widgetWithText(FilledButton, 'Terminar'));
      await tester.pumpAndSettle();
      expect(repo.calls, ['end:a1']);
      expect(find.byKey(const Key('assignment-active-a1')), findsNothing);
      expect(
        find.text('Ari, Andi · desde el 02/11/2026 hasta el 08/11/2026'),
        findsOneWidget,
      );
    },
  );

  testWidgets('an athlete in two plans shows in both', (tester) async {
    final repo = FakeAssignmentRepository(
      items: [
        _assignment('a2', 'p1', athletes: ['ari']),
        _assignment('a1', 'p1'),
      ],
    );
    await _pump(tester, repo, _plans());

    expect(find.byKey(const Key('assignment-active-a1')), findsOneWidget);
    expect(find.byKey(const Key('assignment-active-a2')), findsOneWidget);
    expect(find.text('Ari, Andi\nDesde el 02/11/2026'), findsOneWidget);
    expect(find.text('Ari\nDesde el 02/11/2026'), findsOneWidget);
  });
}
