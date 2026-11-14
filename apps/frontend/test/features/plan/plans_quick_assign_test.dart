import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/asignacion/domain/assignment_repository.dart';
import 'package:maktub_frontend/features/asignacion/presentation/providers.dart';
import 'package:maktub_frontend/features/plan/presentation/plans_page.dart';
import 'package:maktub_ui/maktub_ui.dart';

import 'fakes.dart';

final _audit = Auditoria(creadoPor: 'u1', creadoEn: DateTime.utc(2026, 11, 1));

class _FakeAssignments implements AssignmentRepository {
  _FakeAssignments({this.withActive = false});

  final bool withActive;
  final assigned = <(String, String, DateTime)>[];

  Assignment _active() => Assignment(
    id: 'a1',
    clubId: 'c1',
    planId: 'other',
    groupId: 'g1',
    startDate: DateTime.utc(2026, 11, 2),
    auditoria: _audit,
  );

  @override
  Future<List<AthleteGroup>> groups(String clubId) async => [
    AthleteGroup(id: 'g1', clubId: clubId, name: 'Barra', auditoria: _audit),
  ];

  @override
  Future<List<Assignment>> assignments(
    String clubId, {
    String? groupId,
  }) async => [if (withActive) _active()];

  @override
  Future<Assignment> assign(
    String clubId, {
    required String planId,
    required String groupId,
    required DateTime startDate,
  }) async {
    assigned.add((planId, groupId, startDate));
    return _active();
  }

  @override
  Future<Assignment> end(
    String clubId,
    String assignmentId, {
    DateTime? endDate,
  }) => throw UnimplementedError();
}

void main() {
  final today = DateTime.utc(2026, 11, 8);
  final published = PublishedPlan(
    publishedAt: DateTime.utc(2026, 11, 1),
    publishedBy: 'u1',
  );

  Future<void> open(WidgetTester tester, _FakeAssignments assignments) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...planOverrides(
            FakePlanRepository(
              plans: [
                samplePlan(id: 'p1', name: 'Listo', published: published),
                samplePlan(id: 'p2', name: 'En borrador'),
              ],
            ),
          ),
          assignmentRepositoryProvider.overrideWithValue(assignments),
          assignmentTodayProvider.overrideWithValue(today),
        ],
        child: MaterialApp(
          theme: TemaMaktub.claro(),
          home: const PlansPage(basePath: '/x'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ButtonStyleButton assignButton(WidgetTester tester, String id) =>
      tester.widget<ButtonStyleButton>(find.byKey(Key('plan-assign-$id')));

  testWidgets('a draft keeps the button blocked until it is published', (
    tester,
  ) async {
    await open(tester, _FakeAssignments());
    expect(assignButton(tester, 'p1').onPressed, isNotNull);
    expect(assignButton(tester, 'p2').onPressed, isNull);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('assigns the plan to the group from the card', (tester) async {
    final assignments = _FakeAssignments();
    await open(tester, assignments);
    await tester.tap(find.byKey(const Key('plan-assign-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assign-confirm')));
    await tester.pumpAndSettle();

    expect(assignments.assigned, [('p1', 'g1', today)]);
    expect(find.text('"Listo" asignado a Barra.'), findsOneWidget);
  });

  testWidgets('with a plan in course it explains why and opens nothing', (
    tester,
  ) async {
    final assignments = _FakeAssignments(withActive: true);
    await open(tester, assignments);
    await tester.tap(find.byKey(const Key('plan-assign-p1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('assign-confirm')), findsNothing);
    expect(find.textContaining('ya tiene un plan en curso'), findsOneWidget);
    expect(assignments.assigned, isEmpty);
  });
}
