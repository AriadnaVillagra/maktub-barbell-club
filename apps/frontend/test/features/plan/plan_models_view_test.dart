import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/plan/data/shared_preferences_models_view_store.dart';
import 'package:maktub_frontend/features/plan/presentation/plan_editor_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const prescription = Prescription(exerciseId: 'x', sets: []);

  Plan plan() => samplePlan(
    models: [
      WeekModel(
        id: 'a',
        name: 'A',
        days: [
          PlanDay(
            blocks: [
              PlanBlock(
                name: 'Calentamiento',
                categoryId: 'c',
                prescriptions: [prescription, prescription],
              ),
              PlanBlock(name: 'Primario', categoryId: 'p'),
            ],
          ),
          const PlanDay(),
        ],
      ),
    ],
    assignment: ['a', 'a', 'a', 'a'],
  );

  Future<void> open(WidgetTester tester) => pumpPlanPage(
    tester,
    const PlanEditorPage(planId: 'p1', listPath: '/x'),
    FakePlanRepository(plans: [plan()]),
  );

  testWidgets('the compact view shows each day with its blocks as tags', (
    tester,
  ) async {
    await open(tester);
    expect(find.byKey(const Key('block-a-0-0')), findsOneWidget);
    expect(find.byKey(const Key('day-tags-a-0')), findsNothing);

    await tester.tap(find.text('Compacta'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('block-a-0-0')), findsNothing);
    final tags = find.byKey(const Key('day-tags-a-0'));
    expect(
      find.descendant(of: tags, matching: find.text('Calentamiento · 2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: tags, matching: find.text('Primario')),
      findsOneWidget,
    );
    // An empty day starts open, ready to add blocks.
    expect(find.byKey(const Key('block-add-a-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('day-header-a-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('block-a-0-0')), findsOneWidget);
    expect(find.byKey(const Key('day-tags-a-0')), findsNothing);

    expect(
      (await SharedPreferences.getInstance()).getString(
        SharedPreferencesModelsViewStore.key,
      ),
      'compact',
    );
  });

  testWidgets('a view saved on the device is the one it opens with', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      SharedPreferencesModelsViewStore.key: 'compact',
    });
    await open(tester);
    expect(find.byKey(const Key('day-tags-a-0')), findsOneWidget);
  });

  testWidgets('on a phone both views fit without overflow', (tester) async {
    await open(tester);
    tester.view.physicalSize = const Size(360, 3000);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Compacta'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
