import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/atletas/domain/athlete_repository.dart';
import 'package:maktub_frontend/features/catalogo/presentation/catalog_admin_providers.dart';
import 'package:maktub_frontend/features/plan/domain/athlete_loads.dart';
import 'package:maktub_frontend/features/plan/domain/load_promotion.dart';
import 'package:maktub_frontend/features/plan/domain/prescription_edit.dart';
import 'package:maktub_frontend/features/plan/presentation/plan_editor_page.dart';
import 'package:maktub_frontend/features/plan/presentation/plan_labels.dart';
import 'package:maktub_frontend/features/plan/presentation/prescription_dialog.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../catalogo/catalog_admin_fakes.dart';
import '../catalogo/catalog_fakes.dart' show ex;
import 'fakes.dart';

/// Kilos per athlete in sets in kilos (Ari, 2026-11-21).
final _press = ex(
  'press',
  'Press con mancuerna',
  categories: ['accesorio'],
  metrics: [Metric.fixedLoad, Metric.reps],
);
const _andi = AthleteBasis(id: 'andi', name: 'Andi', rm: null);
const _ari = AthleteBasis(id: 'ari', name: 'Ari', rm: null);
const _both = PrescriptionAthletes(athletes: [_andi, _ari], assigned: true);

final _audit = Auditoria(creadoPor: 'u1', creadoEn: DateTime.utc(2026, 11, 1));
const _people = [
  AthleteSummary(id: 'andi', userId: 'u2', name: 'Andi'),
  AthleteSummary(id: 'ari', userId: 'u1', name: 'Ari'),
];

Assignment _assignment(List<String> athleteIds) => Assignment(
  id: 'a1',
  clubId: 'c1',
  planId: 'p1',
  members: [
    for (final id in athleteIds) AssignmentMember(athleteId: id, from: DateTime.utc(2026, 11, 2)),
  ],
  startDate: DateTime.utc(2026, 11, 2),
  auditoria: _audit,
);

Plan _planWith(List<PlanSet> sets) => samplePlan(
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
              prescriptions: [Prescription(exerciseId: 'press', sets: sets)],
            ),
          ],
        ),
      ],
    ),
  ],
  assignment: ['a', 'a', 'a', 'a'],
);

String _fieldText(WidgetTester tester, String key) => tester
    .widget<TextField>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField)))
    .controller!
    .text;

void main() {
  group('editing kilos per athlete', () {
    test('a set with one weight gives it to each athlete without kilos of their own, and loses it', () {
      final sets = withKgPerAthlete(const [
        PlanSet(reps: 10, kg: 14, byAthlete: {'ari': AthleteSetLoad(kg: 12), 'gone': AthleteSetLoad(kg: 9)}),
        PlanSet(reps: 8),
      ], const ['andi', 'ari']);
      expect(sets.first.kg, isNull);
      expect(sets.first.reps, 10);
      expect(sets.first.byAthlete, {
        'ari': const AthleteSetLoad(kg: 12),
        'gone': const AthleteSetLoad(kg: 9),
        'andi': const AthleteSetLoad(kg: 14),
      });
      expect(sets.last.byAthlete, isEmpty);
    });

    test('one athlete\'s kilos are set or removed, and no general weight is left', () {
      const set = PlanSet(reps: 10, byAthlete: {'ari': AthleteSetLoad(kg: 12)});
      expect(setWithAthleteKg(set, 'andi', 16).byAthlete, {
        'ari': const AthleteSetLoad(kg: 12),
        'andi': const AthleteSetLoad(kg: 16),
      });
      expect(setWithAthleteKg(set, 'ari', null).byAthlete, isEmpty);
      expect(setWithAthleteKg(const PlanSet(reps: 10, kg: 14), 'ari', 12).kg, isNull);
    });

    test('one weight for everyone drops the kilos per athlete, so they do not win in the session', () {
      final set = setWithSingleKg(
        const PlanSet(reps: 10, byAthlete: {'ari': AthleteSetLoad(kg: 12), 'x': AthleteSetLoad(pct: 70, kg: 50)}),
        15,
      );
      expect(set.kg, 15);
      expect(set.byAthlete, {'x': const AthleteSetLoad(pct: 70, kg: 50)});
    });

    test('kilos without % on an exercise without weight go to each athlete', () {
      expect(
        kgToEachAthlete(const [PlanSet(reps: 8, kg: 20)], const ['andi', 'ari']).single.byAthlete,
        {'andi': const AthleteSetLoad(kg: 20), 'ari': const AthleteSetLoad(kg: 20)},
      );
      const withPct = [PlanSet(reps: 8, pct: 60), PlanSet(reps: 8, kg: 20)];
      expect(kgToEachAthlete(withPct, const ['andi', 'ari']), withPct);
    });

    test('kilos per athlete make an exercise without weight a fixed load', () {
      final bulgarian = ex('bulgara', 'Sentadilla búlgara', metrics: [Metric.reps]);
      final w = weightedBySets(bulgarian, const [
        PlanSet(reps: 8, byAthlete: {'ari': AthleteSetLoad(kg: 20)}),
      ])!;
      expect(w.metrics, [Metric.fixedLoad, Metric.reps]);
    });

    test('the summary says the kilos are per athlete', () {
      expect(
        setsSummary(const [
          PlanSet(reps: 10, byAthlete: {'ari': AthleteSetLoad(kg: 12)}),
          PlanSet(reps: 10, byAthlete: {'ari': AthleteSetLoad(kg: 12)}),
        ]),
        '2x10 con kg por atleta',
      );
    });
  });

  group('the prescription dialog', () {
    Future<Future<Prescription?>> open(
      WidgetTester tester, {
      List<PlanSet> sets = const [PlanSet(reps: 10)],
      Exercise? exercise,
      PrescriptionAthletes athletes = _both,
      bool offerLoad = false,
    }) async {
      late Future<Prescription?> result;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [clubTimersProvider.overrideWith((ref) async => const <Temporizador>[])],
          child: MaterialApp(
            theme: TemaMaktub.claro(),
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => result = askPrescription(
                  context,
                  initial: Prescription(exerciseId: (exercise ?? _press).id, sets: sets),
                  exercise: exercise ?? _press,
                  athletes: athletes,
                  offerLoad: offerLoad,
                ),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      return result;
    }

    Future<List<PlanSet>> accept(WidgetTester tester, Future<Prescription?> result) async {
      await tester.tap(find.byKey(const Key('prescription-ok')));
      await tester.pumpAndSettle();
      return (await result)!.sets;
    }

    testWidgets('a plan for two athletes asks each one\'s kilos, with no general weight; reps are shared', (
      tester,
    ) async {
      final result = await open(tester);
      expect(find.byKey(const ValueKey('set-kg-0-0')), findsNothing);
      expect(find.text('Andi (kg)'), findsOneWidget);
      expect(find.text('Ari (kg)'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('set-reps-0-0')), '12');
      await tester.enterText(find.byKey(const ValueKey('set-kg-0-andi-0')), '16');
      await tester.enterText(find.byKey(const ValueKey('set-kg-0-ari-0')), '12,5');
      final set = (await accept(tester, result)).single;
      expect(set.reps, 12);
      expect(set.kg, isNull);
      expect(set.byAthlete, {'andi': const AthleteSetLoad(kg: 16), 'ari': const AthleteSetLoad(kg: 12.5)});
    });

    testWidgets('a set planned with one weight opens with it for each athlete', (tester) async {
      final result = await open(tester, sets: const [PlanSet(reps: 10, kg: 14)]);
      expect(_fieldText(tester, 'set-kg-0-andi-0'), '14');
      expect(_fieldText(tester, 'set-kg-0-ari-0'), '14');

      await tester.enterText(find.byKey(const ValueKey('set-kg-0-ari-0')), '12');
      final set = (await accept(tester, result)).single;
      expect(set.kg, isNull);
      expect(set.byAthlete, {'andi': const AthleteSetLoad(kg: 14), 'ari': const AthleteSetLoad(kg: 12)});
    });

    testWidgets('an added set copies the kilos of each athlete', (tester) async {
      final result = await open(
        tester,
        sets: const [
          PlanSet(reps: 10, byAthlete: {'andi': AthleteSetLoad(kg: 16), 'ari': AthleteSetLoad(kg: 12)}),
        ],
      );
      await tester.tap(find.byKey(const Key('set-add')));
      await tester.pumpAndSettle();
      expect(_fieldText(tester, 'set-kg-1-andi-1'), '16');
      await tester.enterText(find.byKey(const ValueKey('set-kg-1-andi-1')), '18');

      final sets = await accept(tester, result);
      expect(sets.first.byAthlete['andi'], const AthleteSetLoad(kg: 16));
      expect(sets.last.byAthlete, {'andi': const AthleteSetLoad(kg: 18), 'ari': const AthleteSetLoad(kg: 12)});
    });

    testWidgets('a plan for one athlete keeps one weight, and shows theirs', (tester) async {
      final result = await open(
        tester,
        sets: const [
          PlanSet(reps: 10, byAthlete: {'ari': AthleteSetLoad(kg: 12), 'andi': AthleteSetLoad(kg: 16)}),
        ],
        athletes: const PrescriptionAthletes(athletes: [_ari], assigned: true),
      );
      expect(find.byKey(const ValueKey('set-kg-0-ari-0')), findsNothing);
      expect(_fieldText(tester, 'set-kg-0-0'), '12');

      await tester.enterText(find.byKey(const ValueKey('set-kg-0-0')), '13');
      final set = (await accept(tester, result)).single;
      expect(set.kg, 13);
      expect(set.byAthlete, isEmpty);
    });

    testWidgets('a plan not assigned yet keeps one weight, whoever is chosen in Detalles', (tester) async {
      final result = await open(tester, athletes: const PrescriptionAthletes(athletes: [_andi, _ari]));
      expect(find.text('Andi (kg)'), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('set-kg-0-0')), '14');
      final set = (await accept(tester, result)).single;
      expect(set.kg, 14);
      expect(set.byAthlete, isEmpty);
    });

    testWidgets('an exercise by % keeps its % but has no general kg, and offers each athlete\'s kilos by hand with the suggestion below', (tester) async {
      await open(tester, exercise: ex('sq', 'Sentadilla'), sets: const [PlanSet(reps: 5)]);
      expect(find.byKey(const ValueKey('set-pct-0-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('set-kg-0-0')), findsNothing);
      expect(find.byKey(const ValueKey('set-kg-0-andi-0')), findsNothing);
      expect(find.byKey(const ValueKey('set-manual-kg-0-andi-0')), findsOneWidget);
      expect(find.text('Andi (kg)'), findsOneWidget);
      expect(find.byKey(const Key('set-suggestion-0-andi')), findsOneWidget);
      expect(find.textContaining('(sugerido)'), findsNothing);
      final input = tester.getTopLeft(find.byKey(const ValueKey('set-manual-kg-0-andi-0'))).dy;
      expect(tester.getTopLeft(find.byKey(const Key('set-suggestion-0-andi'))).dy, greaterThan(input));
    });

    testWidgets('kilos typed on an exercise without weight go to each athlete', (tester) async {
      final result = await open(
        tester,
        exercise: ex('bulgara', 'Sentadilla búlgara', categories: ['accesorio'], metrics: [Metric.reps]),
        offerLoad: true,
      );
      await tester.enterText(find.byKey(const ValueKey('set-kg-0-0')), '20');
      final set = (await accept(tester, result)).single;
      expect(set.kg, isNull);
      expect(set.byAthlete, {'andi': const AthleteSetLoad(kg: 20), 'ari': const AthleteSetLoad(kg: 20)});
    });
  });

  group('the plan editor', () {
    Future<void> open(WidgetTester tester, {required List<PlanSet> sets, required List<String> athleteIds}) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: planOverrides(
            FakePlanRepository(plans: [_planWith(sets)]),
            catalog: FakeCatalogAdminRepository(
              categoriesList: [category('accesorio', 'Accesorio')],
              exercisesList: [_press],
            ),
            assignments: FakeGroupAssignments([_assignment(athleteIds)]),
            athletes: _people,
          ),
          child: MaterialApp(
            theme: TemaMaktub.claro(),
            home: const PlanEditorPage(planId: 'p1', listPath: '/x'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (find.byKey(const Key('plan-publish')).evaluate().isEmpty) {
        await tester.tap(find.text('Detalles'));
        await tester.pumpAndSettle();
      }
    }

    testWidgets('an assigned plan for two asks each athlete\'s kilos, and cannot be published without them', (
      tester,
    ) async {
      await open(
        tester,
        sets: const [
          PlanSet(reps: 10, byAthlete: {'ari': AthleteSetLoad(kg: 12)}),
        ],
        athleteIds: const ['andi', 'ari'],
      );
      expect(find.textContaining('Faltan los kilos de un atleta en la serie.'), findsOneWidget);
      expect(find.textContaining('Serie 1 › Andi'), findsOneWidget);

      await tester.tap(find.byKey(const Key('prescription-a-0-0-0')));
      await tester.pumpAndSettle();
      expect(_fieldText(tester, 'set-kg-0-ari-0'), '12');
      await tester.enterText(find.byKey(const ValueKey('set-kg-0-andi-0')), '16');
      await tester.tap(find.byKey(const Key('prescription-ok')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Faltan los kilos de un atleta en la serie.'), findsNothing);
      expect(find.text('1x10 con kg por atleta'), findsOneWidget);
    });

    testWidgets('a plan for one athlete is not asked for kilos per athlete', (tester) async {
      await open(tester, sets: const [PlanSet(reps: 10)], athleteIds: const ['ari']);
      expect(find.textContaining('Faltan los kilos'), findsNothing);
      await tester.tap(find.byKey(const Key('prescription-a-0-0-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('set-kg-0-0')), findsOneWidget);
    });
  });
}
