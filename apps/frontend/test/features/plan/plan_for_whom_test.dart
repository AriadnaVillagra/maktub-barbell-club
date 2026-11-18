import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/atletas/domain/athlete_repository.dart';
import 'package:maktub_frontend/features/plan/presentation/plan_editor_page.dart';
import 'package:maktub_ui/maktub_ui.dart';

import 'fakes.dart';

final _audit = Auditoria(creadoPor: 'u1', creadoEn: DateTime.utc(2026, 11, 1));
const _people = [
  AthleteSummary(id: 'andi', userId: 'u2', name: 'Andi'),
  AthleteSummary(id: 'ari', userId: 'u1', name: 'Ari'),
];

/// Who the % and kg are worked out for lives in the plan's Detalles card, for the whole plan (E5.16).
void main() {
  Future<void> open(WidgetTester tester, {List<Assignment> assignments = const []}) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: planOverrides(
          FakePlanRepository(plans: [samplePlan()]),
          assignments: FakeGroupAssignments(assignments),
          athletes: _people,
        ),
        child: MaterialApp(
          theme: TemaMaktub.claro(),
          home: const PlanEditorPage(planId: 'p1', listPath: '/x'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('without an assignment the coach chooses, and the closed card says for whom', (tester) async {
    // The card opens on its own: the sample plan's weeks have no model.
    await open(tester);
    expect(find.text('Calcular % y kg para'), findsOneWidget);
    await tester.tap(find.byKey(const Key('plan-for-whom-andi')));
    await tester.pumpAndSettle();
    final chip = tester.widget<FilterChip>(find.byKey(const Key('plan-for-whom-andi')));
    expect(chip.selected, isFalse);

    await tester.tap(find.text('Detalles'));
    await tester.pumpAndSettle();
    expect(find.text('Para Ari'), findsOneWidget);
  });

  testWidgets('an assigned plan works them out for its assignment, without a choice', (tester) async {
    await open(
      tester,
      assignments: [
        Assignment(
          id: 'a1',
          clubId: 'c1',
          planId: 'p1',
          members: [
            AssignmentMember(athleteId: 'ari', from: DateTime.utc(2026, 11, 2)),
          ],
          startDate: DateTime.utc(2026, 11, 2),
          auditoria: _audit,
        ),
      ],
    );
    expect(find.text('Ari, por la asignación del plan.'), findsOneWidget);
    expect(find.byKey(const Key('plan-for-whom-andi')), findsNothing);
    await tester.tap(find.text('Detalles'));
    await tester.pumpAndSettle();
    expect(find.text('Para Ari'), findsOneWidget);
  });
}
