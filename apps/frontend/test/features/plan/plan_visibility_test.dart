import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/plan/presentation/plan_editor_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// Who else among the club's coaches reaches a plan (pedido de Ari, 2026-11-19). The signed-in user is `u1`, a
/// coach without the club admin role.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // A model with a day, a block and an exercise: every kind of edit control has something to appear on.
  List<WeekModel> models() => [
    WeekModel(
      id: 'a',
      name: 'A',
      days: [
        PlanDay(
          blocks: [
            PlanBlock(
              name: 'Fuerza',
              categoryId: 'c',
              prescriptions: [const Prescription(exerciseId: 'x', sets: [])],
            ),
          ],
        ),
      ],
    ),
  ];
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
    await open(
      tester,
      samplePlan(
        createdBy: 'u9',
        visibility: PlanVisibility.sharedReadOnly,
        models: models(),
        assignment: ['a', 'a', 'a', 'a'],
      ),
    );

    expect(find.byKey(const Key('plan-read-only')), findsOneWidget);
    expect(find.byKey(const Key('plan-save')), findsNothing);
    expect(find.byKey(const Key('plan-delete')), findsNothing);
    expect(find.byKey(const Key('model-add')), findsNothing);
    expect(find.byKey(const Key('plan-copy')), findsOneWidget);
    expect(find.byKey(const Key('plan-publish')), findsNothing);
    // Nothing of the structure can be touched: those controls are gone, not disabled.
    for (final key in [
      'day-add-a',
      'model-menu-a',
      'day-copy-a-0',
      'day-remove-a-0',
      'block-add-a-0',
      'block-drag-a-0-0',
      'block-execution-a-0-0',
      'block-remove-a-0-0',
      'prescription-remove-a-0-0-0',
      'prescription-add-a-0-0',
    ]) {
      expect(find.byKey(Key(key)), findsNothing, reason: key);
    }
    expect(find.byKey(const Key('block-execution-label-a-0-0')), findsOneWidget);
    expect(find.byKey(const Key('block-a-0-0')), findsOneWidget);

    // The compact view still opens a day to look inside.
    await tester.tap(find.text('Compacta'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('block-a-0-0')), findsNothing);
    await tester.tap(find.byKey(const Key('day-header-a-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('block-a-0-0')), findsOneWidget);

    await tester.tap(find.byKey(const Key('plan-details')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plan-visibility')), findsNothing);
    expect(find.text('Compartido para ver'), findsOneWidget);
    // The weeks show their model; there is no menu to change it, nor Activo / Pasado to choose.
    expect(find.byType(DropdownButton<String?>), findsNothing);
    expect(find.byKey(const Key('plan-past')), findsNothing);
    expect(find.byKey(const Key('assign-0')), findsOneWidget);
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
