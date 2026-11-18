import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/asignacion/domain/assignment_repository.dart';
import 'package:maktub_frontend/features/asignacion/presentation/providers.dart';
import 'package:maktub_frontend/features/atletas/domain/athlete_repository.dart';
import 'package:maktub_frontend/features/plan/presentation/plans_page.dart';
import 'package:maktub_ui/maktub_ui.dart';

import 'fakes.dart';

final _audit = Auditoria(creadoPor: 'u1', creadoEn: DateTime.utc(2026, 11, 1));

class _FakeAssignments implements AssignmentRepository {
  _FakeAssignments({this.withActive = false});

  final bool withActive;
  final assigned = <String>[];

  Assignment _active() => Assignment(
    id: 'a1',
    clubId: 'c1',
    planId: 'other',
    members: [AssignmentMember(athleteId: 'ari', from: DateTime.utc(2026, 11, 2))],
    startDate: DateTime.utc(2026, 11, 2),
    auditoria: _audit,
  );

  @override
  Future<List<AthleteGroup>> groups(String clubId) async => const [];

  @override
  Future<List<Assignment>> assignments(
    String clubId, {
    String? groupId,
  }) async => [if (withActive) _active()];

  @override
  Future<Assignment> assign(
    String clubId, {
    required String planId,
    required List<String> athleteIds,
    required DateTime startDate,
  }) async {
    assigned.add('$planId:${athleteIds.join(',')}:${aIsoFecha(startDate)}');
    return _active();
  }

  @override
  Future<Assignment> setAthletes(
    String clubId,
    String assignmentId, {
    required List<String> athleteIds,
    required DateTime date,
  }) => throw UnimplementedError();

  @override
  Future<Assignment> end(
    String clubId,
    String assignmentId, {
    DateTime? endDate,
  }) => throw UnimplementedError();
}

const _ari = AthleteSummary(id: 'ari', userId: 'u1', name: 'Ari');
const _andi = AthleteSummary(id: 'andi', userId: 'u2', name: 'Andi');

void main() {
  final today = DateTime.utc(2026, 11, 8);
  final published = PublishedPlan(
    publishedAt: DateTime.utc(2026, 11, 1),
    publishedBy: 'u1',
  );

  Future<void> open(
    WidgetTester tester,
    _FakeAssignments assignments, {
    List<AthleteSummary> athletes = const [],
  }) async {
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
            assignments: assignments,
            athletes: athletes,
          ),
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

  testWidgets('without athletes in the club it says so and opens nothing', (
    tester,
  ) async {
    final assignments = _FakeAssignments();
    await open(tester, assignments);
    await tester.tap(find.byKey(const Key('plan-assign-p1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('assign-confirm')), findsNothing);
    expect(find.text('Todavía no hay atletas en el club.'), findsOneWidget);
  });

  testWidgets('assigns the plan to every athlete chosen, all at first', (
    tester,
  ) async {
    final assignments = _FakeAssignments();
    await open(tester, assignments, athletes: const [_ari, _andi]);
    await tester.tap(find.byKey(const Key('plan-assign-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assign-confirm')));
    await tester.pumpAndSettle();

    expect(assignments.assigned, ['p1:ari,andi:2026-11-08']);
    expect(find.text('"Listo" asignado a Ari, Andi.'), findsOneWidget);
  });

  testWidgets(
    'an athlete with a plan in course can get another one (E6.7)',
    (tester) async {
      final assignments = _FakeAssignments(withActive: true);
      await open(tester, assignments, athletes: const [_ari, _andi]);
      await tester.tap(find.byKey(const Key('plan-assign-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('assign-athlete-andi')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('assign-confirm')));
      await tester.pumpAndSettle();

      expect(assignments.assigned, ['p1:ari:2026-11-08']);
      expect(find.text('"Listo" asignado a Ari.'), findsOneWidget);
    },
  );

  testWidgets('with nobody chosen it cannot assign', (tester) async {
    await open(tester, _FakeAssignments(), athletes: const [_ari]);
    await tester.tap(find.byKey(const Key('plan-assign-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('assign-athlete-ari')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('assign-confirm')))
          .onPressed,
      isNull,
    );
  });
}
