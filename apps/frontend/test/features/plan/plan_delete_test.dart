import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/plan/presentation/plan_editor_page.dart';
import 'package:maktub_frontend/features/plan/presentation/plans_page.dart';
import 'package:maktub_ui/maktub_ui.dart';

import 'fakes.dart';

/// E8.9: "Eliminar plan" in the editor asks first, deletes, and goes back to the list without the plan.
void main() {
  Future<void> openEditor(WidgetTester tester, FakePlanRepository repo) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/planes/p1',
      routes: [
        GoRoute(
          path: '/planes',
          builder: (_, _) => const PlansPage(basePath: '/planes'),
          routes: [
            GoRoute(
              path: ':id',
              builder: (_, state) => PlanEditorPage(planId: state.pathParameters['id']!, listPath: '/planes'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: planOverrides(repo),
        child: MaterialApp.router(theme: TemaMaktub.claro(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  FakePlanRepository twoPlans() => FakePlanRepository(
    plans: [samplePlan(id: 'p1', name: 'Fuerza'), samplePlan(id: 'p2', name: 'Otro')],
  );

  testWidgets('confirming deletes the plan and goes back to the list without it', (tester) async {
    final repo = twoPlans();
    await openEditor(tester, repo);

    await tester.tap(find.byKey(const Key('plan-delete')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Las series que ya se registraron'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await tester.pumpAndSettle();

    expect(repo.calls, contains('delete:c1:p1'));
    expect(find.byType(PlansPage), findsOneWidget);
    expect(find.text('Otro'), findsOneWidget);
    expect(find.text('Fuerza'), findsNothing);
  });

  testWidgets('cancelling deletes nothing and stays in the editor', (tester) async {
    final repo = twoPlans();
    await openEditor(tester, repo);

    await tester.tap(find.byKey(const Key('plan-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(repo.calls.where((c) => c.startsWith('delete')), isEmpty);
    expect(repo.stored.keys, containsAll(['p1', 'p2']));
    expect(find.byType(PlanEditorPage), findsOneWidget);
  });

  testWidgets('a failed delete shows the server message and stays in the editor', (tester) async {
    final repo = twoPlans()..deleteFailure = const ErrorDeApi('Plan no encontrado.', estado: 404);
    await openEditor(tester, repo);

    await tester.tap(find.byKey(const Key('plan-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await tester.pumpAndSettle();

    expect(find.text('Plan no encontrado.'), findsOneWidget);
    expect(find.byType(PlanEditorPage), findsOneWidget);
  });
}
