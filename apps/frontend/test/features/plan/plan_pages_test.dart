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
import 'package:maktub_ui/maktub_ui.dart';

import '../catalogo/catalog_admin_fakes.dart';
import '../catalogo/catalog_fakes.dart' show ex;
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
      for (final tag in ['Regular', '2 modelos', 'RM', '0 modelos']) {
        expect(find.text(tag), findsOneWidget);
      }
      expect(find.text('Borrador'), findsNWidgets(2));
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
          child: MaterialApp.router(theme: TemaMaktub.claro(), routerConfig: router),
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

      // Days have no move arrows.
      expect(find.byKey(const Key('day-up-a-0')), findsNothing);
      expect(find.byKey(const Key('day-down-a-0')), findsNothing);

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
            child: MaterialApp.router(theme: TemaMaktub.claro(), routerConfig: router),
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

  group('blocks', () {
    final catalog = FakeCatalogAdminRepository(
      categoriesList: [
        category('warm', 'Calentamiento'),
        category('main', 'Principal'),
        category('old', 'Vieja', status: CatalogStatus.archived),
      ],
      timersList: [
        timer('rest90', 'Descanso 90'),
        timer('emom', 'EMOM 10', type: TipoTemporizador.emom),
        timer('gone', 'Archivado', status: CatalogStatus.archived),
      ],
    );

    Future<void> open(WidgetTester tester, [Plan? plan]) async {
      await pumpPlanPage(
        tester,
        const PlanEditorPage(planId: 'p1', listPath: '/x'),
        FakePlanRepository(
          plans: [
            plan ??
                samplePlan(
                  models: [model('a', 'A', 1)],
                  assignment: ['a', 'a', 'a', 'a'],
                ),
          ],
        ),
        catalog: catalog,
      );
    }

    Future<void> pick(WidgetTester tester, Key field, String text) async {
      await tester.tap(find.byKey(field));
      await tester.pumpAndSettle();
      await tester.tap(find.text(text).last);
      await tester.pumpAndSettle();
    }

    Future<void> addBlock(
      WidgetTester tester,
      String name,
      String category, {
      String? timer,
    }) async {
      await tester.tap(find.byKey(const Key('block-add-a-0')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('block-name-field')), name);
      await pick(tester, const Key('block-category-field'), category);
      if (timer != null) {
        await pick(tester, const Key('block-timer-field'), timer);
      }
      await tester.tap(find.byKey(const Key('block-ok')));
      await tester.pumpAndSettle();
    }

    testWidgets('a new day starts empty; the dialog needs name and category', (
      tester,
    ) async {
      await open(tester);
      expect(find.byKey(const Key('block-a-0-0')), findsNothing);
      await tester.tap(find.byKey(const Key('block-add-a-0')));
      await tester.pumpAndSettle();
      FilledButton ok() =>
          tester.widget<FilledButton>(find.byKey(const Key('block-ok')));
      expect(ok().onPressed, isNull);
      await tester.enterText(find.byKey(const Key('block-name-field')), 'WoD');
      await tester.pump();
      expect(ok().onPressed, isNull, reason: 'the category is required');
      await pick(tester, const Key('block-category-field'), 'Principal');
      expect(ok().onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('block-category-field')));
      await tester.pumpAndSettle();
      expect(find.text('Vieja'), findsNothing, reason: 'archived is hidden');
    });

    testWidgets('builds the 5 reference blocks with name, category and timer', (
      tester,
    ) async {
      await open(tester);
      const names = ['Estiramiento', 'Calentamiento', 'Principal', 'Final'];
      for (final n in names) {
        await addBlock(tester, n, 'Calentamiento');
      }
      await addBlock(tester, 'WoD', 'Principal', timer: 'Descanso 90');
      expect(find.byKey(const Key('block-a-0-5')), findsNothing);
      for (var i = 0; i < 5; i++) {
        expect(find.byKey(Key('block-a-0-$i')), findsOneWidget);
      }
      expect(find.text('Principal · Temporizador: Descanso 90'), findsOneWidget);
      expect(find.byKey(const Key('plan-dirty')), findsOneWidget);

      await tester.tap(find.byKey(const Key('block-add-a-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('block-timer-field')));
      await tester.pumpAndSettle();
      expect(find.text('Descanso 90'), findsOneWidget);
      expect(
        find.text('EMOM 10'),
        findsOneWidget,
        reason: 'every active timer, of any type',
      );
      expect(find.text('Archivado'), findsNothing);
    });

    testWidgets('a block can be edited and removed, and has no move arrows', (
      tester,
    ) async {
      await open(tester);
      await addBlock(tester, 'Uno', 'Calentamiento');
      await addBlock(tester, 'Dos', 'Principal');
      expect(find.byTooltip('Subir bloque'), findsNothing);
      expect(find.byTooltip('Bajar bloque'), findsNothing);

      await tester.tap(find.byKey(const Key('block-a-0-0')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('block-name-field')))
            .controller!
            .text,
        'Uno',
      );
      await tester.enterText(
        find.byKey(const Key('block-name-field')),
        'Uno bis',
      );
      await pick(tester, const Key('block-category-field'), 'Principal');
      await pick(tester, const Key('block-timer-field'), 'Descanso 90');
      await tester.tap(find.byKey(const Key('block-ok')));
      await tester.pumpAndSettle();
      expect(find.text('Uno bis'), findsOneWidget);
      expect(find.text('Principal · Temporizador: Descanso 90'), findsOneWidget);

      await tester.tap(find.byKey(const Key('block-remove-a-0-1')));
      await tester.pump();
      expect(find.text('Dos'), findsNothing);
      expect(find.byKey(const Key('block-a-0-1')), findsNothing);
    });

    testWidgets('an empty block stays empty', (tester) async {
      await open(tester);
      await addBlock(tester, 'Final', 'Principal');
      expect(find.text('Final'), findsOneWidget);
      expect(find.byKey(const Key('prescription-a-0-0-0')), findsNothing);
    });
  });

  group('prescriptions', () {
    final squat = ex('squat', 'Sentadilla', categories: ['primario']);
    final curl = ex(
      'curl',
      'Curl',
      categories: ['primario'],
      metrics: const [Metric.fixedLoad, Metric.reps],
    );
    final plank = ex(
      'plank',
      'Plancha',
      categories: ['wod'],
      metrics: const [Metric.time],
    );

    FakeCatalogAdminRepository catalog({bool withRestTimers = true}) =>
        FakeCatalogAdminRepository(
          categoriesList: [category('primario', 'Primario'), category('wod', 'WoD')],
          timersList: [
            if (withRestTimers) timer('desc_180', 'Descanso 3 min', work: 180),
          ],
          exercisesList: [squat, curl, plank],
        );

    Future<void> open(
      WidgetTester tester,
      String categoryId, {
      bool withRestTimers = true,
    }) => pumpPlanPage(
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
                  PlanDay(
                    blocks: [PlanBlock(name: 'Bloque', categoryId: categoryId)],
                  ),
                ],
              ),
            ],
            assignment: ['a', 'a', 'a', 'a'],
          ),
        ],
      ),
      catalog: catalog(withRestTimers: withRestTimers),
    );

    Future<void> add(WidgetTester tester, String name) async {
      await tester.tap(find.byKey(const Key('prescription-add-a-0-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }

    testWidgets('the picker only offers exercises of the block category', (
      tester,
    ) async {
      await open(tester, 'primario');
      await tester.tap(find.byKey(const Key('prescription-add-a-0-0')));
      await tester.pumpAndSettle();
      expect(find.text('Sentadilla'), findsOneWidget);
      expect(find.text('Curl'), findsOneWidget);
      expect(find.text('Plancha'), findsNothing);
    });

    testWidgets('a percent exercise arrives with the reference sets and timer', (
      tester,
    ) async {
      await open(tester, 'primario');
      expect(find.byKey(const Key('prescription-a-0-0-0')), findsNothing);
      await add(tester, 'Sentadilla');
      expect(find.text('Sentadilla'), findsOneWidget);
      expect(find.text('1x8 al 65 %, 1x5 al 72,5 %, 2x3 al 80 %'), findsOneWidget);
      expect(find.text('Temporizador: Descanso 3 min'), findsOneWidget);
      expect(find.byKey(const Key('plan-dirty')), findsOneWidget);
    });

    testWidgets('a fixed-load exercise arrives with reps and no percent', (
      tester,
    ) async {
      await open(tester, 'primario');
      await add(tester, 'Curl');
      expect(find.text('1x8, 1x5, 2x3'), findsOneWidget);
      expect(
        find.text('Temporizador: Descanso 3 min'),
        findsOneWidget,
      );
    });

    testWidgets('without the default timer in the club it stays empty', (
      tester,
    ) async {
      await open(tester, 'primario', withRestTimers: false);
      await add(tester, 'Sentadilla');
      expect(find.text('1x8 al 65 %, 1x5 al 72,5 %, 2x3 al 80 %'), findsOneWidget);
      expect(find.textContaining('Temporizador:'), findsNothing);
    });

    testWidgets('a WoD block offers exercises of every category', (tester) async {
      await open(tester, 'wod');
      await add(tester, 'Sentadilla');
      expect(find.byKey(const Key('prescription-a-0-0-0')), findsOneWidget);
      expect(find.text('Sentadilla'), findsOneWidget);
    });

    testWidgets('a block of another category gets no defaults', (tester) async {
      await open(tester, 'wod');
      await add(tester, 'Plancha');
      expect(find.byKey(const Key('prescription-a-0-0-0')), findsOneWidget);
      expect(find.text('Plancha'), findsOneWidget);
      expect(find.textContaining('Temporizador:'), findsNothing);
      expect(find.textContaining(RegExp(r'\dx\d')), findsNothing);
    });

    testWidgets('dismissing the picker adds nothing; prescriptions are removed', (
      tester,
    ) async {
      await open(tester, 'primario');
      await tester.tap(find.byKey(const Key('prescription-add-a-0-0')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('prescription-a-0-0-0')), findsNothing);

      await add(tester, 'Sentadilla');
      await add(tester, 'Curl');
      expect(find.byKey(const Key('prescription-a-0-0-1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('prescription-remove-a-0-0-0')));
      await tester.pumpAndSettle();
      expect(find.text('Sentadilla'), findsNothing);
      expect(find.byKey(const Key('prescription-a-0-0-1')), findsNothing);
      await tester.tap(find.byKey(const Key('prescription-remove-a-0-0-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('prescription-a-0-0-0')), findsNothing);
      expect(find.text('Curl'), findsNothing, reason: 'an empty block stays empty');
    });
  });

  group('editing a prescription', () {
    final squat = ex('squat', 'Sentadilla', categories: ['primario']);
    final curl = ex(
      'curl',
      'Curl',
      categories: ['primario'],
      metrics: const [Metric.fixedLoad, Metric.reps],
    );

    Future<void> open(WidgetTester tester) => pumpPlanPage(
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
                  PlanDay(
                    blocks: [
                      PlanBlock(
                        name: 'Bloque',
                        categoryId: 'primario',
                        prescriptions: const [
                          Prescription(
                            exerciseId: 'squat',
                            sets: [
                              PlanSet(reps: 8, pct: 65),
                              PlanSet(reps: 5, pct: 72.5),
                            ],
                          ),
                          Prescription(
                            exerciseId: 'curl',
                            sets: [PlanSet(reps: 10, kg: 12.5)],
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
            assignment: ['a', 'a', 'a', 'a'],
          ),
        ],
      ),
      catalog: FakeCatalogAdminRepository(
        categoriesList: [category('primario', 'Primario')],
        timersList: [
          timer('desc_180', 'Descanso 3 min', work: 180),
          timer('desc_90', 'Descanso 90 s', work: 90),
        ],
        exercisesList: [squat, curl],
      ),
    );

    Future<void> openFirst(WidgetTester tester, [int p = 0]) async {
      await open(tester);
      await tester.tap(find.byKey(Key('prescription-a-0-0-$p')));
      await tester.pumpAndSettle();
    }

    Future<void> accept(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('prescription-ok')));
      await tester.pumpAndSettle();
    }

    testWidgets('percent exercise shows reps and %, and edits each set', (
      tester,
    ) async {
      await openFirst(tester);
      expect(find.byKey(const Key('set-row-1')), findsOneWidget);
      expect(find.byKey(const Key('set-kg-0-0')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('set-reps-0-0')), '6');
      await tester.enterText(find.byKey(const ValueKey('set-pct-1-0')), '75,5');
      await accept(tester);
      expect(find.text('1x6 al 65 %, 1x5 al 75,5 %'), findsOneWidget);
      expect(find.byKey(const Key('plan-dirty')), findsOneWidget);
    });

    testWidgets('fixed-load exercise shows reps and kg, no %', (tester) async {
      await openFirst(tester, 1);
      expect(find.byKey(const ValueKey('set-kg-0-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('set-pct-0-0')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('set-kg-0-0')), '15');
      await accept(tester);
      await tester.tap(find.byKey(const Key('prescription-a-0-0-1')));
      await tester.pumpAndSettle();
      expect(find.text('15'), findsOneWidget);
    });

    testWidgets('numeric fields do not accept letters', (tester) async {
      await openFirst(tester);
      await tester.enterText(find.byKey(const ValueKey('set-reps-0-0')), '1a2');
      await tester.enterText(find.byKey(const ValueKey('set-pct-0-0')), '7x0,5');
      await tester.enterText(find.byKey(const Key('prescription-bar-field')), '1b5');
      await tester.pump();
      expect(find.text('12'), findsOneWidget);
      expect(find.text('70,5'), findsNothing);
      expect(find.text('7x0,5'), findsNothing);
      await accept(tester);
      expect(find.textContaining('1x12 al '), findsOneWidget);
    });

    testWidgets('adding a set copies the previous one; removing keeps one', (
      tester,
    ) async {
      await openFirst(tester);
      await tester.tap(find.byKey(const Key('set-add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('set-row-2')), findsOneWidget);
      await accept(tester);
      expect(find.text('1x8 al 65 %, 2x5 al 72,5 %'), findsOneWidget);

      await tester.tap(find.byKey(const Key('prescription-a-0-0-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('set-remove-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('set-remove-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('set-row-1')), findsNothing);
      final last = tester.widget<IconButton>(find.byKey(const Key('set-remove-0')));
      expect(last.onPressed, isNull);
      await accept(tester);
      expect(find.text('1x5 al 72,5 %'), findsOneWidget);
    });

    testWidgets('note, own timer and bar are stored; empty timer uses the block', (
      tester,
    ) async {
      await openFirst(tester);
      await tester.enterText(
        find.byKey(const Key('prescription-note-field')),
        'RPE 8',
      );
      await tester.enterText(find.byKey(const Key('prescription-bar-field')), '15,5');
      await tester.tap(find.byKey(const Key('prescription-timer-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Descanso 90 s').last);
      await tester.pumpAndSettle();
      await accept(tester);
      expect(find.text('1x8 al 65 %, 1x5 al 72,5 %'), findsOneWidget);
      expect(
        find.text('Temporizador: Descanso 90 s · Barra: 15,5 kg · RPE 8'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('prescription-a-0-0-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prescription-timer-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('El del bloque').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('prescription-bar-field')), '');
      await tester.enterText(find.byKey(const Key('prescription-note-field')), '');
      await accept(tester);
      expect(find.text('1x8 al 65 %, 1x5 al 72,5 %'), findsOneWidget);
    });

    testWidgets('cancelling changes nothing', (tester) async {
      await openFirst(tester);
      await tester.enterText(find.byKey(const ValueKey('set-reps-0-0')), '1');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('1x8 al 65 %, 1x5 al 72,5 %'), findsOneWidget);
      expect(find.byKey(const Key('plan-dirty')), findsNothing);
    });
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
        expect(find.text('Calendario'), findsOneWidget);
      },
    );

    testWidgets('a coach reaches the WoD library from Preferencias', (
      tester,
    ) async {
      await mount(tester, {Rol.coach});
      await tester.tap(find.text('Preferencias'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('preferencia-${Rutas.wods}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('wods-empty')), findsOneWidget);
      await tester.tap(find.byKey(const Key('wod-add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('wod-name-field')), findsOneWidget);
    });

    testWidgets('who cannot plan does not see WoDs in Preferencias', (
      tester,
    ) async {
      await mount(tester, {Rol.adminClub});
      await tester.tap(find.text('Preferencias'));
      await tester.pumpAndSettle();
      expect(find.text('Miembros'), findsOneWidget);
      expect(find.text('WoDs'), findsNothing);
    });
  });
}
