import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/plan/presentation/plan_editor_page.dart';

import 'fakes.dart';

/// Who else among the club's coaches reaches a plan (pedido de Ari, 2026-11-19). The signed-in user is `u1`, a
/// coach without the club admin role.
void main() {
  Future<FakePlanRepository> open(WidgetTester tester, Plan plan) async {
    final repo = FakePlanRepository(plans: [plan]);
    await pumpPlanPage(tester, PlanEditorPage(planId: plan.id, listPath: '/planes'), repo);
    return repo;
  }

  testWidgets('its creator chooses who sees it, and the choice is saved with the plan', (tester) async {
    final repo = await open(tester, samplePlan());

    expect(find.byKey(const Key('plan-read-only')), findsNothing);
    expect(find.byKey(const Key('plan-delete')), findsOneWidget);

    await tester.tap(find.byKey(const Key('plan-details')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Para ver'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plan-dirty')), findsOneWidget);

    await tester.tap(find.byKey(const Key('plan-save')));
    await tester.pumpAndSettle();

    expect(repo.saved.single.visibility, PlanVisibility.sharedReadOnly);
  });

  testWidgets("another coach's plan shared read-only: no save, delete or visibility choice", (tester) async {
    await open(tester, samplePlan(createdBy: 'u9', visibility: PlanVisibility.sharedReadOnly));

    expect(find.byKey(const Key('plan-read-only')), findsOneWidget);
    expect(find.byKey(const Key('plan-save')), findsNothing);
    expect(find.byKey(const Key('plan-delete')), findsNothing);
    expect(find.byKey(const Key('model-add')), findsNothing);
    expect(find.byKey(const Key('plan-copy')), findsOneWidget);

    await tester.tap(find.byKey(const Key('plan-details')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plan-visibility')), findsNothing);
    expect(find.text('Compartido para ver'), findsOneWidget);
  });

  testWidgets("another coach's plan shared editable: saved, but neither deleted nor its visibility changed", (
    tester,
  ) async {
    await open(tester, samplePlan(createdBy: 'u9', visibility: PlanVisibility.sharedEditable));

    expect(find.byKey(const Key('plan-read-only')), findsNothing);
    expect(find.byKey(const Key('plan-save')), findsOneWidget);
    expect(find.byKey(const Key('plan-delete')), findsNothing);

    await tester.tap(find.byKey(const Key('plan-details')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plan-visibility')), findsNothing);
  });
}
