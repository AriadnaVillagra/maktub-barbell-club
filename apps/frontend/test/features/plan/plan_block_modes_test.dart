import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/plan/presentation/plan_editor_page.dart';

import '../catalogo/catalog_admin_fakes.dart';
import 'fakes.dart';

void main() {
  Future<void> open(WidgetTester tester, PlanBlock block) => pumpPlanPage(
    tester,
    const PlanEditorPage(planId: 'p1', listPath: '/x'),
    FakePlanRepository(
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

  testWidgets('the coach picks the execution and athlete modes of a block', (
    tester,
  ) async {
    await open(tester, const PlanBlock(name: 'Fuerza', categoryId: 'primario'));
    expect(selected<ExecutionMode>(tester, 'block-execution-a-0-0'), {
      ExecutionMode.sequential,
    });
    expect(selected<AthleteMode>(tester, 'block-athletes-a-0-0'), {
      AthleteMode.simultaneous,
    });
    expect(find.byKey(const Key('plan-dirty')), findsNothing);

    await tester.tap(find.text('Circuito'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Por turnos'));
    await tester.pumpAndSettle();

    expect(selected<ExecutionMode>(tester, 'block-execution-a-0-0'), {
      ExecutionMode.circuit,
    });
    expect(selected<AthleteMode>(tester, 'block-athletes-a-0-0'), {
      AthleteMode.turns,
    });
    expect(find.byKey(const Key('plan-dirty')), findsOneWidget);

    await tester.tap(find.text('Secuencial'));
    await tester.pumpAndSettle();
    expect(selected<ExecutionMode>(tester, 'block-execution-a-0-0'), {
      ExecutionMode.sequential,
    });
    expect(selected<AthleteMode>(tester, 'block-athletes-a-0-0'), {
      AthleteMode.turns,
    });
  });

  testWidgets('a wod block does not show the mode controls', (tester) async {
    await open(tester, const PlanBlock(name: 'WoD', categoryId: 'wod'));
    expect(find.byKey(const Key('block-execution-a-0-0')), findsNothing);
    expect(find.byKey(const Key('block-athletes-a-0-0')), findsNothing);
    expect(find.text('Circuito'), findsNothing);
  });
}
