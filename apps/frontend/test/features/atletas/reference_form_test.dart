import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/atletas/domain/athlete_repository.dart';
import 'package:maktub_frontend/features/atletas/domain/reference_form_rules.dart';
import 'package:maktub_frontend/features/atletas/presentation/athlete_sheet_page.dart';

import '../catalogo/catalog_fakes.dart';
import 'fakes.dart';

void main() {
  final exercises = [
    ex('sq', 'Sentadilla'),
    ex(
      'curl',
      'Curl con mancuernas',
      metrics: const [Metric.fixedLoad, Metric.reps],
    ),
    ex(
      'pull',
      'Dominadas',
      metrics: const [Metric.bodyweight, Metric.reps],
    ),
  ];

  FakeAthleteRepository repoWith({Object? writeFailure}) =>
      FakeAthleteRepository(
        writeFailure: writeFailure,
        sheets: {
          'a1': AthleteSheet(
            athleteId: 'a1',
            references: [rm('r1', 'sq', 100, DateTime.utc(2026, 1, 1))],
            factors: [factor('f1', 'sq', 90, DateTime.utc(2026, 9, 1))],
          ),
        },
      );

  Future<void> open(
    WidgetTester tester,
    FakeAthleteRepository repo, {
    Set<Rol> roles = const {Rol.coach},
  }) => pumpAthletePage(
    tester,
    const AthleteSheetPage(athleteId: 'a1'),
    repo,
    exercises: exercises,
    roles: roles,
  );

  Future<void> fill(WidgetTester tester, String exercise, String value) async {
    await tester.tap(find.byKey(const Key('form-exercise')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(exercise).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('form-value')), value);
  }

  testWidgets(
    'an RM is saved with today as the default date and the factor reads 100 %',
    (tester) async {
      final repo = repoWith();
      await open(tester, repo);
      expect(find.text('Vigente: 90 %'), findsOneWidget);
      await tester.tap(find.byKey(const Key('edit-rm')));
      await tester.pumpAndSettle();
      expect(find.text('Desde 08/11/2026'), findsOneWidget);
      await fill(tester, 'Sentadilla', '130,5');
      await tester.tap(find.byKey(const Key('form-save')));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('rm:sq:130.5:2026-11-08'));
      expect(repo.calls.where((c) => c.startsWith('factor')), isEmpty);
      expect(find.byKey(const Key('rm-new')), findsOneWidget);
      expect(find.byKey(const Key('rm-r1')), findsOneWidget);
      expect(find.text('Vigente: 100 %'), findsOneWidget);
    },
  );

  testWidgets(
    'a new factor shows up and the previous one stays in the history',
    (tester) async {
      final repo = repoWith();
      await open(tester, repo);
      await tester.tap(find.byKey(const Key('edit-factor')));
      await tester.pumpAndSettle();
      await fill(tester, 'Sentadilla', '85');
      await tester.tap(find.byKey(const Key('form-save')));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('factor:sq:85.0:2026-11-08'));
      expect(find.text('Vigente: 85 %'), findsOneWidget);
      expect(find.text('90 % desde 01/09/2026'), findsOneWidget);
    },
  );

  testWidgets('the fixed weight can be set for an exercise with no data yet', (
    tester,
  ) async {
    final repo = repoWith();
    await open(tester, repo);
    await tester.tap(find.byKey(const Key('edit-fixedWeight')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('form-date')), findsNothing);
    await fill(tester, 'Curl con mancuernas', '12.5');
    await tester.tap(find.byKey(const Key('form-save')));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('fixed:curl:12.5'));
    expect(find.byKey(const Key('fixed-curl')), findsOneWidget);
    expect(find.text('12.5 kg'), findsOneWidget);
  });

  testWidgets('the RM form only offers exercises loaded by % of RM', (
    tester,
  ) async {
    await open(tester, repoWith());
    await tester.tap(find.byKey(const Key('edit-rm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('form-exercise')));
    await tester.pumpAndSettle();
    expect(find.text('Sentadilla'), findsWidgets);
    expect(find.text('Curl con mancuernas'), findsNothing);
    expect(find.text('Dominadas'), findsNothing);
  });

  testWidgets('the exercise picker of the forms filters by category', (
    tester,
  ) async {
    final repo = FakeAthleteRepository(
      sheets: {'a1': const AthleteSheet(athleteId: 'a1')},
    );
    await pumpAthletePage(
      tester,
      const AthleteSheetPage(athleteId: 'a1'),
      repo,
      exercises: [
        ex('sq', 'Sentadilla'),
        ex('bench', 'Press banca', categories: const ['accessory']),
      ],
    );
    await tester.tap(find.byKey(const Key('edit-rm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('form-exercise')));
    await tester.pumpAndSettle();
    expect(find.text('Sentadilla'), findsOneWidget);
    expect(find.text('Press banca'), findsOneWidget);

    await tester.tap(find.byKey(const Key('category-chip-accessory')).last);
    await tester.pumpAndSettle();
    expect(find.text('Sentadilla'), findsNothing);
    expect(find.text('Press banca'), findsOneWidget);
  });

  testWidgets('the fixed weight form explains itself too', (tester) async {
    await open(tester, repoWith());
    await tester.tap(find.byKey(const Key('edit-fixedWeight')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('form-help')));
    await tester.pumpAndSettle();
    expect(find.textContaining('no se carga por porcentaje'), findsOneWidget);
    await tester.tap(find.byKey(const Key('form-exercise')));
    await tester.pumpAndSettle();
  });

  testWidgets('the factor form explains itself with a tap, the RM form does not', (
    tester,
  ) async {
    await open(tester, repoWith());
    await tester.tap(find.byKey(const Key('edit-rm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('form-help')), findsNothing);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('edit-factor')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('form-help')));
    await tester.pumpAndSettle();
    expect(find.textContaining('un máximo menor al RM'), findsOneWidget);

    await tester.tap(find.byKey(const Key('form-exercise')));
    await tester.pumpAndSettle();
    expect(find.textContaining('un máximo menor al RM'), findsNothing);
  });

  testWidgets('the fixed weight form only offers fixed-load exercises', (
    tester,
  ) async {
    await open(tester, repoWith());
    await tester.tap(find.byKey(const Key('edit-fixedWeight')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('form-exercise')));
    await tester.pumpAndSettle();
    expect(find.text('Curl con mancuernas'), findsOneWidget);
    expect(find.text('Dominadas'), findsNothing);
  });

  testWidgets(
    'the form asks for an exercise and a positive value before saving',
    (tester) async {
      final repo = repoWith();
      await open(tester, repo);
      await tester.tap(find.byKey(const Key('edit-rm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('form-save')));
      await tester.pumpAndSettle();
      expect(find.text('Elegí un ejercicio.'), findsOneWidget);
      await fill(tester, 'Sentadilla', '0');
      await tester.tap(find.byKey(const Key('form-save')));
      await tester.pumpAndSettle();
      expect(find.text('Ingresá un valor mayor que cero.'), findsOneWidget);
      expect(repo.calls.where((c) => c.startsWith('rm')), isEmpty);
    },
  );

  testWidgets('a backend error is shown in the form, which stays open', (
    tester,
  ) async {
    final repo = repoWith(
      writeFailure: const ErrorDeApi('El valor es inválido.', estado: 400),
    );
    await open(tester, repo);
    await tester.tap(find.byKey(const Key('edit-factor')));
    await tester.pumpAndSettle();
    await fill(tester, 'Sentadilla', '85');
    await tester.tap(find.byKey(const Key('form-save')));
    await tester.pumpAndSettle();
    expect(find.text('El valor es inválido.'), findsOneWidget);
    expect(find.byKey(const Key('form-save')), findsOneWidget);
  });

  testWidgets('an athlete does not see the edit controls', (tester) async {
    await open(tester, repoWith(), roles: {Rol.atleta});
    expect(find.byKey(const Key('rm-r1')), findsOneWidget);
    expect(find.byKey(const Key('edit-rm')), findsNothing);
    expect(find.byKey(const Key('edit-factor')), findsNothing);
    expect(find.byKey(const Key('edit-fixedWeight')), findsNothing);
  });

  test(
    'parsePositive accepts comma or point and rejects zero, negatives and text',
    () {
      expect(parsePositive(' 12,5 '), 12.5);
      expect(parsePositive('80'), 80);
      expect(parsePositive('0'), isNull);
      expect(parsePositive('-3'), isNull);
      expect(parsePositive('abc'), isNull);
      expect(parsePositive(''), isNull);
    },
  );
}
