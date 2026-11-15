import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/plan/presentation/plan_editor_page.dart';

import '../catalogo/catalog_admin_fakes.dart';
import 'fakes.dart';

void main() {
  late FakePlanRepository repo;

  Future<void> open(WidgetTester tester, PlanBlock block) => pumpPlanPage(
    tester,
    const PlanEditorPage(planId: 'p1', listPath: '/x'),
    repo = FakePlanRepository(
      plans: [
        samplePlan(
          models: [
            WeekModel(
              id: 'a',
              name: 'A',
              days: [
                PlanDay(blocks: [block]),
              ],
            ),
          ],
          assignment: ['a', 'a', 'a', 'a'],
        ),
      ],
    ),
    catalog: FakeCatalogAdminRepository(
      categoriesList: [
        category('primario', 'Primario'),
        category('wod', 'WoD'),
      ],
    ),
  );

  Set<Object> selected<T>(WidgetTester tester, String key) => tester
      .widget<SegmentedButton<T>>(find.byKey(Key(key)))
      .selected
      .cast<Object>();

  testWidgets(
    'the coach picks the execution mode; the athlete mode is not in the editor',
    (tester) async {
      await open(
        tester,
        const PlanBlock(
          name: 'Fuerza',
          categoryId: 'primario',
          athleteMode: AthleteMode.turns,
        ),
      );
      expect(selected<ExecutionMode>(tester, 'block-execution-a-0-0'), {
        ExecutionMode.sequential,
      });
      expect(find.byKey(const Key('block-athletes-a-0-0')), findsNothing);
      expect(find.text('Por turnos'), findsNothing);
      expect(find.byKey(const Key('plan-dirty')), findsNothing);

      await tester.tap(find.text('Circuito'));
      await tester.pumpAndSettle();
      expect(selected<ExecutionMode>(tester, 'block-execution-a-0-0'), {
        ExecutionMode.circuit,
      });
      expect(find.byKey(const Key('plan-dirty')), findsOneWidget);

      // The block keeps the athlete mode it had.
      await tester.tap(find.byKey(const Key('plan-save')));
      await tester.pumpAndSettle();
      expect(
        repo.saved.last.weekModels.single.days.single.blocks.single.athleteMode,
        AthleteMode.turns,
      );
    },
  );

  testWidgets('on a phone the mode sits next to the name without overflow', (
    tester,
  ) async {
    await open(
      tester,
      const PlanBlock(name: 'Estiramiento largo', categoryId: 'primario'),
    );
    tester.view.physicalSize = const Size(360, 3000);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('block-execution-a-0-0')), findsOneWidget);
  });

  testWidgets('a wod block does not show the mode controls', (tester) async {
    await open(tester, const PlanBlock(name: 'WoD', categoryId: 'wod'));
    expect(find.byKey(const Key('block-execution-a-0-0')), findsNothing);
    expect(find.byKey(const Key('block-athletes-a-0-0')), findsNothing);
    expect(find.text('Circuito'), findsNothing);
  });
}
