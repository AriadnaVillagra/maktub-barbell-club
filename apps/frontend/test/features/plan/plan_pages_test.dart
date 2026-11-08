import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/app/app.dart';
import 'package:maktub_frontend/app/router.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/plan/presentation/plan_editor_page.dart';
import 'package:maktub_frontend/features/plan/presentation/plans_page.dart';
import 'package:maktub_frontend/features/session/presentation/providers.dart';

import '../session/fakes.dart';
import 'fakes.dart';

Plan reference() => samplePlan(
  models: [model('a', 'A', 3), model('b', 'B', 3)],
  assignment: ['a', 'b', 'b', 'a'],
);

void main() {
  group('plan list', () {
    testWidgets('shows the club plans with type and model count', (
      tester,
    ) async {
      final repo = FakePlanRepository(
        plans: [
          reference(),
          samplePlan(id: 'p2', name: 'Test 1RM', type: PlanType.test),
        ],
      );
      await pumpPlanPage(tester, const PlansPage(basePath: '/x'), repo);
      expect(find.text('Fuerza'), findsOneWidget);
      expect(find.text('Regular · 2 modelos'), findsOneWidget);
      expect(find.text('Test · 0 modelos'), findsOneWidget);
      expect(repo.calls, ['plans:c1']);
    });

    testWidgets('empty state and backend error', (tester) async {
      await pumpPlanPage(
        tester,
        const PlansPage(basePath: '/x'),
        FakePlanRepository(),
      );
      expect(find.byKey(const Key('plans-empty')), findsOneWidget);

      await pumpPlanPage(
        tester,
        const PlansPage(basePath: '/x'),
        FakePlanRepository(
          failure: const ErrorDeApi('Sin permiso.', estado: 403),
        ),
      );
      expect(find.text('Sin permiso.'), findsOneWidget);
    });

    testWidgets('creates a plan with name and type, then opens its editor', (
      tester,
    ) async {
      final repo = FakePlanRepository();
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        initialLocation: '/planes',
        routes: [
          GoRoute(
            path: '/planes',
            builder: (_, _) => const PlansPage(basePath: '/planes'),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, s) => PlanEditorPage(
                  planId: s.pathParameters['id']!,
                  listPath: '/planes',
                ),
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: planOverrides(repo),
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('plan-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('plan-create-ok')));
      await tester.pumpAndSettle();
      expect(
        repo.calls.where((c) => c.startsWith('create')),
        isEmpty,
        reason: 'a name is required',
      );

      await tester.enterText(
        find.byKey(const Key('plan-name-field')),
        '  Hipertrofia ',
      );
      await tester.tap(find.byKey(const Key('plan-type-test')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('plan-create-ok')));
      await tester.pumpAndSettle();

      expect(repo.calls, contains('create:c1:Hipertrofia:test'));
      expect(find.byKey(const Key('models-empty')), findsOneWidget);
      expect(find.text('Hipertrofia'), findsOneWidget);
    });
  });

  group('editor', () {
    Future<FakePlanRepository> open(WidgetTester tester, [Plan? plan]) async {
      final repo = FakePlanRepository(plans: [plan ?? reference()]);
      await pumpPlanPage(
        tester,
        const PlanEditorPage(planId: 'p1', listPath: '/x'),
        repo,
      );
      return repo;
    }

    String? selected(WidgetTester tester, int week) => tester
        .widget<DropdownButton<String?>>(find.byKey(Key('assign-$week')))
        .value;

    testWidgets('shows the models, the 4 assignments and the days', (
      tester,
    ) async {
      await open(tester);
      expect(find.byKey(const Key('model-a')), findsOneWidget);
      expect(find.byKey(const Key('model-b')), findsOneWidget);
      expect(
        [for (var w = 0; w < 4; w++) selected(tester, w)],
        ['a', 'b', 'b', 'a'],
      );
      expect(find.byKey(const Key('day-a-2')), findsOneWidget);
      expect(find.byKey(const Key('plan-dirty')), findsNothing);
    });

    testWidgets('builds A, B, B, A with 3 days from an empty plan', (
      tester,
    ) async {
      await open(tester, samplePlan());
      expect(find.byKey(const Key('models-empty')), findsOneWidget);

      for (final name in ['A', 'B']) {
        await tester.tap(find.byKey(const Key('model-add')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('plan-name-field')))
              .controller!
              .text,
          name,
        );
        await tester.tap(find.byKey(const Key('plan-name-ok')));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const Key('plan-dirty')), findsOneWidget);

      for (final (week, name) in [(0, 'A'), (1, 'B'), (2, 'B'), (3, 'A')]) {
        await tester.tap(find.byKey(Key('assign-$week')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(name).last);
        await tester.pumpAndSettle();
      }
      expect(
        [for (var w = 0; w < 4; w++) selected(tester, w)],
        ['m1', 'm2', 'm2', 'm1'],
      );

      for (final id in ['m1', 'm2']) {
        for (var i = 0; i < 2; i++) {
          await tester.tap(find.byKey(Key('day-add-$id')));
          await tester.pump();
        }
        expect(find.byKey(Key('day-$id-2')), findsOneWidget);
      }
    });

    testWidgets(
      'a model can be renamed and removed; removing unassigns its weeks',
      (tester) async {
        await open(tester);
        await tester.tap(find.byKey(const Key('model-rename-a')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('plan-name-field')),
          'Fuerza',
        );
        await tester.tap(find.byKey(const Key('plan-name-ok')));
        await tester.pumpAndSettle();
        expect(find.text('Fuerza'), findsWidgets);

        await tester.tap(find.byKey(const Key('model-remove-a')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('model-a')), findsNothing);
        expect(
          [for (var w = 0; w < 4; w++) selected(tester, w)],
          [null, 'b', 'b', null],
        );
      },
    );

    testWidgets('days can be added up to 7, removed down to 1 and reordered', (
      tester,
    ) async {
      await open(
        tester,
        samplePlan(
          models: [model('a', 'A', 6)],
          assignment: ['a', 'a', 'a', 'a'],
        ),
      );
      await tester.tap(find.byKey(const Key('day-add-a')));
      await tester.pump();
      expect(find.byKey(const Key('day-a-6')), findsOneWidget);
      expect(find.text('Máximo 7 días'), findsOneWidget);
      expect(
        tester.widget<TextButton>(find.byKey(const Key('day-add-a'))).onPressed,
        isNull,
      );

      // Day 1 moves down: the day titled "Da1" is now second.
      expect(find.text('Da1'), findsOneWidget);
      await tester.tap(find.byKey(const Key('day-down-a-0')));
      await tester.pump();
      expect(
        tester.getTopLeft(find.text('Da1')).dy >
            tester.getTopLeft(find.text('Da2')).dy,
        isTrue,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('day-up-a-0')))
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const Key('day-remove-a-0')));
      await tester.pump();
      expect(find.byKey(const Key('day-a-6')), findsNothing);
    });

    testWidgets('the last day of a model cannot be removed', (tester) async {
      await open(
        tester,
        samplePlan(
          models: [model('a', 'A', 1)],
          assignment: ['a', 'a', 'a', 'a'],
        ),
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('day-remove-a-0')))
            .onPressed,
        isNull,
      );
    });

    testWidgets(
      'leaving with unsaved changes asks first; without changes it leaves',
      (tester) async {
        final repo = FakePlanRepository(plans: [reference()]);
        tester.view.physicalSize = const Size(900, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final router = GoRouter(
          initialLocation: '/planes',
          routes: [
            GoRoute(
              path: '/planes',
              builder: (_, _) => const Scaffold(body: Text('lista')),
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (_, s) =>
                      PlanEditorPage(planId: 'p1', listPath: '/planes'),
                ),
              ],
            ),
          ],
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: planOverrides(repo),
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        router.go('/planes/p1');
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('day-add-a')));
        await tester.pump();
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('plan-discard')), findsOneWidget);

        await tester.tap(find.byKey(const Key('plan-keep-editing')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('day-a-3')), findsOneWidget);

        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('plan-discard')));
        await tester.pumpAndSettle();
        expect(find.text('lista'), findsOneWidget);

        router.go('/planes/p1');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('day-a-3')),
          findsNothing,
          reason: 'discarded changes are gone',
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('lista'), findsOneWidget);
      },
    );
  });

  group('navigation', () {
    Future<void> mount(WidgetTester tester, Set<Rol> roles) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStoreProvider.overrideWithValue(FakeTokenStore(issued(1))),
            authApiProvider.overrideWithValue(FakeAuthApi()),
            ...planOverrides(
              FakePlanRepository(plans: [reference()]),
              roles: roles,
            ).skip(1),
          ],
          child: const MaktubApp(),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a coach reaches the list and the editor from Planificación', (
      tester,
    ) async {
      await mount(tester, {Rol.coach});
      await tester.tap(find.text('Planificación'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('portada-${Rutas.planes}')));
      await tester.pumpAndSettle();
      expect(find.text('Fuerza'), findsOneWidget);
      await tester.tap(find.byKey(const Key('plan-p1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('model-a')), findsOneWidget);
    });

    testWidgets(
      'a non-coach does not see the planning section nor reach the plan routes',
      (tester) async {
        await mount(tester, {Rol.atleta});
        expect(find.text('Planificación'), findsNothing);
        GoRouter.of(tester.element(find.byType(Scaffold).first))
            .go(Rutas.planes);
        await tester.pumpAndSettle();
        expect(find.text('Fuerza'), findsNothing);
        expect(find.text('Sesión de hoy'), findsOneWidget);
      },
    );
  });
}
