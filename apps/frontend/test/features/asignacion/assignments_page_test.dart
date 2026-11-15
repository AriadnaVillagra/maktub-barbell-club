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
  String? athleteId,
}) => Assignment(
  id: id,
  clubId: 'c1',
  planId: planId,
  groupId: athleteId == null ? 'g1' : null,
  athleteId: athleteId,
  startDate: DateTime.utc(2026, 11, 2),
  status: status,
  endDate: end,
  auditoria: _audit,
);

class FakeAssignmentRepository implements AssignmentRepository {
  FakeAssignmentRepository({
    this.hasGroup = true,
    List<Assignment> items = const [],
  }) : items = [...items];

  final bool hasGroup;
  final List<Assignment> items;
  final calls = <String>[];
  Object? assignFailure;

  @override
  Future<List<AthleteGroup>> groups(String clubId) async => [
    if (hasGroup)
      AthleteGroup(id: 'g1', clubId: clubId, name: 'Barra', auditoria: _audit),
  ];

  @override
  Future<List<Assignment>> assignments(
    String clubId, {
    String? groupId,
  }) async => [...items];

  @override
  Future<Assignment> assign(
    String clubId, {
    required String planId,
    String? groupId,
    String? athleteId,
    required DateTime startDate,
  }) async {
    calls.add('assign:$planId:${groupId ?? athleteId}:${aIsoFecha(startDate)}');
    if (assignFailure != null) throw assignFailure!;
    final a = Assignment(
      id: 'a${items.length + 1}',
      clubId: clubId,
      planId: planId,
      groupId: groupId,
      athleteId: athleteId,
      startDate: startDate,
      auditoria: _audit,
    );
    items.insert(0, a);
    return a;
  }

  @override
  Future<Assignment> end(
    String clubId,
    String assignmentId, {
    DateTime? endDate,
  }) async {
    calls.add('end:$assignmentId');
    final i = items.indexWhere((a) => a.id == assignmentId);
    final ended = _assignment(
      assignmentId,
      items[i].planId,
      status: AssignmentStatus.ended,
      end: DateTime.utc(2026, 11, 8),
      athleteId: items[i].athleteId,
    );
    items[i] = ended;
    return ended;
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
  List<AthleteSummary> athletes = const [],
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
  testWidgets('without a group it says so and offers no add button', (
    tester,
  ) async {
    await _pump(tester, FakeAssignmentRepository(hasGroup: false), _plans());
    expect(find.byKey(const Key('assignments-no-group')), findsOneWidget);
    expect(find.byKey(const Key('assignment-new')), findsNothing);
  });

  testWidgets('assigns a published plan with the date defaulting to today', (
    tester,
  ) async {
    final repo = FakeAssignmentRepository();
    await _pump(tester, repo, _plans());
    expect(find.byKey(const Key('assignment-none-active-grupo-g1')), findsOneWidget);
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
    await tester.tap(find.byKey(const Key('assign-confirm')));
    await tester.pumpAndSettle();

    expect(repo.calls, ['assign:p1:g1:2026-11-08']);
    expect(find.byKey(const Key('assignment-active-grupo-g1')), findsOneWidget);
    expect(find.text('Activa desde el 08/11/2026'), findsOneWidget);
    // The only owner has an active one: no way to assign another.
    expect(find.byKey(const Key('assignment-new')), findsNothing);
  });

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

  testWidgets(
    'ending asks first; cancelling keeps it, confirming moves it to earlier',
    (tester) async {
      final repo = FakeAssignmentRepository(items: [_assignment('a1', 'p1')]);
      await _pump(tester, repo, _plans());
      expect(find.byKey(const Key('assignment-new')), findsNothing);

      await tester.tap(find.byKey(const Key('assignment-end-grupo-g1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(repo.calls, isEmpty);

      await tester.tap(find.byKey(const Key('assignment-end-grupo-g1')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Terminar'));
      await tester.pumpAndSettle();
      expect(repo.calls, ['end:a1']);
      expect(find.byKey(const Key('assignment-active-grupo-g1')), findsNothing);
      expect(
        find.text('Terminada · desde el 02/11/2026 hasta el 08/11/2026'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('assignment-new')), findsOneWidget);
    },
  );

  group("an athlete's own plan (E8.8)", () {
    testWidgets(
      'with the group busy a plan goes to an athlete, listed under their name',
      (tester) async {
        final repo = FakeAssignmentRepository(items: [_assignment('a1', 'p1')]);
        await _pump(tester, repo, _plans(), athletes: _athletes);
        // Athletes without a plan of their own are not listed, but can get one.
        expect(find.text('Ari'), findsNothing);
        expect(find.byKey(const Key('assignment-new')), findsOneWidget);

        await tester.tap(find.byKey(const Key('assignment-new')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('assign-owner')));
        await tester.pumpAndSettle();
        // The busy group is not offered: only the section title says "Grupo Barra".
        expect(find.text('Grupo Barra'), findsOneWidget);
        expect(find.text('Andi'), findsWidgets);
        await tester.tap(find.text('Ari').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('assign-confirm')));
        await tester.pumpAndSettle();

        expect(repo.calls, ['assign:p1:ari:2026-11-08']);
        expect(find.byKey(const Key('assignment-active-grupo-g1')), findsOneWidget);
        expect(find.byKey(const Key('assignment-active-atleta-ari')), findsOneWidget);
        expect(find.text('Ari'), findsOneWidget);
      },
    );

    testWidgets("ending an athlete's plan leaves the group's alone", (
      tester,
    ) async {
      final repo = FakeAssignmentRepository(
        items: [
          _assignment('a2', 'p1', athleteId: 'ari'),
          _assignment('a1', 'p1'),
        ],
      );
      await _pump(tester, repo, _plans(), athletes: _athletes);
      await tester.tap(find.byKey(const Key('assignment-end-atleta-ari')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Terminar'));
      await tester.pumpAndSettle();

      expect(repo.calls, ['end:a2']);
      expect(find.byKey(const Key('assignment-active-grupo-g1')), findsOneWidget);
      expect(find.byKey(const Key('assignment-none-active-atleta-ari')), findsOneWidget);
    });
  });
}
