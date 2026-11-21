import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/catalogo/presentation/exercise_catalog_providers.dart';
import 'package:maktub_frontend/features/plan/domain/load_promotion.dart';
import 'package:maktub_frontend/features/plan/presentation/plan_editor_page.dart';
import 'package:maktub_frontend/features/plan/presentation/plan_labels.dart';

import '../catalogo/catalog_admin_fakes.dart';
import '../catalogo/catalog_fakes.dart' show ex;
import 'fakes.dart';

/// Given without "con peso" in the catalog (Ari, 2026-11-21).
final bulgarian = ex(
  'bulgara',
  'Sentadilla búlgara',
  categories: ['accesorio'],
  metrics: [Metric.reps],
);

Plan planWith(List<PlanSet> sets) => samplePlan(
  models: [
    WeekModel(
      id: 'a',
      name: 'A',
      days: [
        PlanDay(
          blocks: [
            PlanBlock(
              name: 'Accesorios',
              categoryId: 'accesorio',
              prescriptions: [Prescription(exerciseId: 'bulgara', sets: sets)],
            ),
          ],
        ),
      ],
    ),
  ],
  assignment: ['a', 'a', 'a', 'a'],
);

void main() {
  group('weightedBySets', () {
    test('a % makes it loaded by % of RM, with its own RM since it measures reps', () {
      final w = weightedBySets(bulgarian, const [PlanSet(reps: 8, pct: 60), PlanSet(reps: 8)])!;
      expect(w.metrics, [Metric.loadPctRm, Metric.reps]);
      expect(w.loadReference, const LoadReference.own());
      expect(w.measuresLoadTimesReps, isTrue);
    });

    test('kilos alone make it a fixed load, without a reference', () {
      final w = weightedBySets(bulgarian, const [PlanSet(reps: 8, kg: 20)])!;
      expect(w.metrics, [Metric.fixedLoad, Metric.reps]);
      expect(w.loadReference, const LoadReference.none());
    });

    test('a % on an exercise that does not measure reps keeps it without a reference', () {
      final plank = ex('plancha', 'Plancha', metrics: [Metric.time]);
      final w = weightedBySets(plank, const [PlanSet(pct: 50)])!;
      expect(w.metrics, [Metric.loadPctRm, Metric.time]);
      expect(w.loadReference, const LoadReference.none());
    });

    test('blank stays without weight, and a weighted one is left alone', () {
      expect(weightedBySets(bulgarian, const [PlanSet(reps: 8)]), isNull);
      expect(weightedBySets(bulgarian, const [PlanSet(reps: 8, kg: 0)]), isNull);
      expect(weightedBySets(ex('sq', 'Sentadilla'), const [PlanSet(reps: 5, kg: 100)]), isNull);
    });

    test('only the exercises the user can write, gathered from every model', () {
      final plan = planWith(const [PlanSet(reps: 8, kg: 20)]);
      final catalog = {'bulgara': bulgarian};
      expect(exercisesGainingLoad(plan, catalog, canWrite: (_) => true).keys, ['bulgara']);
      expect(exercisesGainingLoad(plan, catalog, canWrite: (_) => false), isEmpty);
    });
  });

  test('the notices name the exercises', () {
    expect(gainedLoadNotices(['Sentadilla búlgara'], const []), ['Sentadilla búlgara ahora tiene peso']);
    expect(gainedLoadNotices(['A', 'B', 'C'], const []), ['A, B y C ahora tienen peso']);
    expect(gainedLoadNotices(const [], const []), isEmpty);
    expect(gainedLoadNotices(const [], ['A']).single, startsWith('No se pudo guardar con peso: A.'));
  });

  group('the plan editor', () {
    late FakePlanRepository repo;
    late FakeCatalogAdminRepository catalog;

    Future<void> open(
      WidgetTester tester, {
      List<PlanSet> sets = const [PlanSet(reps: 8)],
      Set<Rol> roles = const {Rol.coach, Rol.adminClub},
      Exercise? exercise,
      bool isPlatformAdmin = false,
    }) async {
      repo = FakePlanRepository(plans: [planWith(sets)]);
      catalog = FakeCatalogAdminRepository(
        categoriesList: [category('accesorio', 'Accesorio')],
        exercisesList: [exercise ?? bulgarian],
      );
      await pumpPlanPage(
        tester,
        const PlanEditorPage(planId: 'p1', listPath: '/x'),
        repo,
        catalog: catalog,
        roles: roles,
        isPlatformAdmin: isPlatformAdmin,
      );
      await tester.tap(find.byKey(const Key('prescription-a-0-0-0')));
      await tester.pumpAndSettle();
    }

    Future<void> acceptAndSave(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('prescription-ok')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('plan-save')));
      await tester.pumpAndSettle();
    }

    Exercise savedExercise() => catalog.exercisesList.single;

    testWidgets('an exercise without weight offers % and kg anyway', (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('set-pct-0-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('set-kg-0-0')), findsOneWidget);
    });

    testWidgets('kilos typed: the plan is saved and the exercise becomes weighted, with a notice', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const ValueKey('set-kg-0-0')), '20');
      await acceptAndSave(tester);

      expect(repo.saved.single.weekModels.single.days.single.blocks.single.prescriptions.single.sets.single.kg, 20);
      expect(catalog.updatedExercises.map((u) => u.$1), ['bulgara']);
      expect(savedExercise().metrics, [Metric.fixedLoad, Metric.reps]);
      expect(find.text('Sentadilla búlgara ahora tiene peso'), findsOneWidget);
    });

    testWidgets('a % typed makes it loaded by % with its own RM, and the editor sees it weighted', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const ValueKey('set-pct-0-0')), '60');
      await acceptAndSave(tester);

      expect(savedExercise().metrics, [Metric.loadPctRm, Metric.reps]);
      expect(savedExercise().loadReference, const LoadReference.own());
      final container = ProviderScope.containerOf(tester.element(find.byType(PlanEditorPage)));
      expect((await container.read(catalogExercisesProvider.future)).single.metrics, contains(Metric.loadPctRm));
    });

    testWidgets('left blank, nothing changes in the catalog', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const ValueKey('set-reps-0-0')), '10');
      await acceptAndSave(tester);

      expect(repo.saved, hasLength(1));
      expect(catalog.updatedExercises, isEmpty);
      expect(find.textContaining('ahora tiene peso'), findsNothing);
    });

    testWidgets('a coach who cannot change the catalog gets no weight fields, as before', (tester) async {
      await open(tester, roles: const {Rol.coach});
      expect(find.byKey(const ValueKey('set-pct-0-0')), findsNothing);
      expect(find.byKey(const ValueKey('set-kg-0-0')), findsNothing);
    });

    testWidgets('a default exercise needs a platform admin', (tester) async {
      final base = ex('bulgara', 'Sentadilla búlgara', clubId: clubPlataforma, categories: ['accesorio'], metrics: [Metric.reps]);
      await open(tester, exercise: base);
      expect(find.byKey(const ValueKey('set-kg-0-0')), findsNothing);
    });

    testWidgets('a platform admin makes a default exercise weighted', (tester) async {
      final base = ex('bulgara', 'Sentadilla búlgara', clubId: clubPlataforma, categories: ['accesorio'], metrics: [Metric.reps]);
      await open(tester, exercise: base, isPlatformAdmin: true);
      await tester.enterText(find.byKey(const ValueKey('set-kg-0-0')), '20');
      await acceptAndSave(tester);
      expect(savedExercise().metrics, contains(Metric.fixedLoad));
      expect(savedExercise().clubId, clubPlataforma);
    });

    testWidgets('a failed catalog write keeps the plan saved and says the next save retries', (tester) async {
      await open(tester);
      catalog.updateExerciseFailure = Exception('offline');
      await tester.enterText(find.byKey(const ValueKey('set-kg-0-0')), '20');
      await acceptAndSave(tester);

      expect(repo.saved, hasLength(1));
      expect(savedExercise().metrics, [Metric.reps]);
      expect(find.textContaining('No se pudo guardar con peso: Sentadilla búlgara.'), findsOneWidget);
    });
  });
}
