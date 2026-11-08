import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/plan/presentation/plan_editor_page.dart';

import '../catalogo/catalog_admin_fakes.dart';
import '../catalogo/catalog_fakes.dart' show ex;
import '../wods/fakes.dart';
import 'fakes.dart';

void main() {
  final squat = ex('squat', 'Sentadilla', categories: ['primario']);
  final plank = ex(
    'plank',
    'Plancha',
    categories: ['wod'],
    metrics: const [Metric.time],
  );

  final fran = sampleWod(
    id: 'w1',
    name: 'Fran',
    description: '21-15-9 de thrusters',
    timerId: 'amrap',
    prescriptions: const [
      Prescription(
        exerciseId: 'squat',
        sets: [PlanSet(reps: 21), PlanSet(reps: 15), PlanSet(reps: 9)],
      ),
      Prescription(exerciseId: 'plank'),
    ],
  );
  final murph = sampleWod(id: 'w2', name: 'Murph');

  FakeCatalogAdminRepository catalog() => FakeCatalogAdminRepository(
    categoriesList: [category('primario', 'Primario'), category('wod', 'WoD')],
    timersList: [
      timer('amrap', 'AMRAP 12', type: TipoTemporizador.amrap),
      timer('mine', 'Descanso 90'),
    ],
    exercisesList: [squat, plank],
  );

  FakePlanRepository planRepo(PlanBlock block) => FakePlanRepository(
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
  );

  Future<void> open(
    WidgetTester tester,
    PlanBlock block,
    FakeWodRepository wods, {
    FakePlanRepository? plans,
  }) => pumpPlanPage(
    tester,
    const PlanEditorPage(planId: 'p1', listPath: '/x'),
    plans ?? planRepo(block),
    catalog: catalog(),
    wods: wods,
  );

  Future<void> addWod(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(const Key('wod-add-a-0-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  const wodBlock = PlanBlock(name: 'WoD del día', categoryId: 'wod');

  testWidgets(
    'only a WoD block offers Agregar WoD, besides Agregar ejercicio',
    (tester) async {
      await open(tester, wodBlock, FakeWodRepository(wods: [fran]));
      expect(find.text('Agregar WoD'), findsOneWidget);
      expect(find.text('Agregar ejercicio'), findsOneWidget);

      await open(
        tester,
        const PlanBlock(name: 'Fuerza', categoryId: 'primario'),
        FakeWodRepository(wods: [fran]),
      );
      expect(find.text('Agregar WoD'), findsNothing);
      expect(find.text('Agregar ejercicio'), findsOneWidget);
    },
  );

  testWidgets('the picker lists every WoD of the club, and the empty library', (
    tester,
  ) async {
    await open(tester, wodBlock, FakeWodRepository(wods: [murph, fran]));
    await tester.tap(find.byKey(const Key('wod-add-a-0-0')));
    await tester.pumpAndSettle();
    expect(find.text('Fran'), findsOneWidget);
    expect(find.text('Murph'), findsOneWidget);
    expect(find.text('2 ejercicios · Temporizador: AMRAP 12'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('prescription-a-0-0-0')), findsNothing);

    await open(tester, wodBlock, FakeWodRepository());
    await tester.tap(find.byKey(const Key('wod-add-a-0-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('wod-picker-empty')), findsOneWidget);
  });

  testWidgets('choosing a WoD copies its timer, note and exercises with sets', (
    tester,
  ) async {
    await open(tester, wodBlock, FakeWodRepository(wods: [fran]));
    await addWod(tester, 'Fran');
    expect(find.text('WoD · Temporizador: AMRAP 12'), findsOneWidget);
    expect(find.text('21-15-9 de thrusters'), findsOneWidget);
    expect(find.text('Sentadilla'), findsOneWidget);
    expect(find.text('1x21, 1x15, 1x9'), findsOneWidget);
    expect(find.text('Plancha'), findsOneWidget);
    expect(find.byKey(const Key('plan-dirty')), findsOneWidget);
  });

  testWidgets('a block with its own timer and note keeps them', (tester) async {
    await open(
      tester,
      const PlanBlock(
        name: 'WoD del día',
        categoryId: 'wod',
        timerId: 'mine',
        note: 'Mi nota',
      ),
      FakeWodRepository(wods: [fran]),
    );
    await addWod(tester, 'Fran');
    expect(find.text('WoD · Temporizador: Descanso 90'), findsOneWidget);
    expect(find.text('Mi nota'), findsOneWidget);
    expect(find.text('21-15-9 de thrusters'), findsNothing);
    expect(find.text('Sentadilla'), findsOneWidget);
  });

  testWidgets('the copy can be adjusted without touching the library', (
    tester,
  ) async {
    final wods = FakeWodRepository(wods: [fran]);
    await open(tester, wodBlock, wods);
    await addWod(tester, 'Fran');

    await tester.tap(find.byKey(const Key('prescription-a-0-0-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('set-remove-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('prescription-ok')));
    await tester.pumpAndSettle();
    expect(find.text('1x21, 1x15'), findsOneWidget);
    await tester.tap(find.byKey(const Key('prescription-remove-a-0-0-1')));
    await tester.pumpAndSettle();

    expect(wods.stored['w1']!.prescriptions, hasLength(2));
    expect(wods.stored['w1']!.prescriptions[0].sets, hasLength(3));
    expect(wods.calls.where((c) => !c.startsWith('wods')), isEmpty);
  });

  testWidgets(
    'editing the WoD later does not change the saved plan, nor does deleting it',
    (tester) async {
      final wods = FakeWodRepository(wods: [fran]);
      final plans = planRepo(wodBlock);
      await open(tester, wodBlock, wods, plans: plans);
      await addWod(tester, 'Fran');
      await tester.tap(find.byKey(const Key('plan-save')));
      await tester.pumpAndSettle();

      // The library changes and then loses the WoD.
      wods.stored['w1'] = sampleWod(
        id: 'w1',
        name: 'Fran',
        timerId: 'mine',
        prescriptions: const [Prescription(exerciseId: 'plank')],
      );
      wods.stored.remove('w1');

      final block = plans.stored['p1']!.weekModels[0].days[0].blocks[0];
      expect(block.timerId, 'amrap');
      expect(block.note, '21-15-9 de thrusters');
      expect(
        [for (final p in block.prescriptions) p.exerciseId],
        ['squat', 'plank'],
      );
      expect(block.prescriptions[0].sets, hasLength(3));
    },
  );

  testWidgets('the block dialog shows and edits the note', (tester) async {
    await open(
      tester,
      const PlanBlock(name: 'WoD del día', categoryId: 'wod', note: 'Vieja'),
      FakeWodRepository(),
    );
    expect(find.text('Vieja'), findsOneWidget);
    await tester.tap(find.text('WoD del día'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('block-note-field')))
          .controller!
          .text,
      'Vieja',
    );
    await tester.enterText(
      find.byKey(const Key('block-note-field')),
      ' Nueva ',
    );
    await tester.tap(find.byKey(const Key('block-ok')));
    await tester.pumpAndSettle();
    expect(find.text('Nueva'), findsOneWidget);
    expect(find.text('Vieja'), findsNothing);

    await tester.tap(find.text('WoD del día'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('block-note-field')), '  ');
    await tester.tap(find.byKey(const Key('block-ok')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('block-note-a-0-0')), findsNothing);
  });

  testWidgets('a new block can be created with a note', (tester) async {
    await pumpPlanPage(
      tester,
      const PlanEditorPage(planId: 'p1', listPath: '/x'),
      FakePlanRepository(
        plans: [
          samplePlan(
            models: [model('a', 'A', 1)],
            assignment: ['a', 'a', 'a', 'a'],
          ),
        ],
      ),
      catalog: catalog(),
    );
    await tester.tap(find.byKey(const Key('block-add-a-0')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('block-name-field')), 'WoD');
    await tester.tap(find.byKey(const Key('block-category-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WoD').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('block-note-field')),
      'Escalar',
    );
    await tester.tap(find.byKey(const Key('block-ok')));
    await tester.pumpAndSettle();
    expect(find.text('Escalar'), findsOneWidget);
  });
}
