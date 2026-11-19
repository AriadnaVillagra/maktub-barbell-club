import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_frontend/features/plan/presentation/plans_page.dart';

import 'fakes.dart';

/// E8.10: what another coach changes (sharing, hiding, deleting) shows up without reloading the page.
void main() {
  testWidgets('the list is asked for again when the app comes back to the front', (tester) async {
    final repo = FakePlanRepository(plans: [samplePlan(id: 'p1', name: 'Fuerza'), samplePlan(id: 'p2', name: 'Otro')]);
    await pumpPlanPage(tester, const PlansPage(basePath: '/planes'), repo);
    expect(find.text('Otro'), findsOneWidget);

    // Another coach makes it private meanwhile.
    repo.stored.remove('p2');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Fuerza'), findsOneWidget);
    expect(find.text('Otro'), findsNothing);
  });
}
