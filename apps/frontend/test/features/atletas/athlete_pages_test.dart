import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/atletas/domain/athlete_repository.dart';
import 'package:maktub_frontend/features/atletas/presentation/athlete_sheet_page.dart';
import 'package:maktub_frontend/features/atletas/presentation/athletes_page.dart';

import '../catalogo/catalog_fakes.dart';
import 'fakes.dart';

void main() {
  final exercises = [ex('sq', 'Sentadilla'), ex('curl', 'Curl con mancuernas')];

  testWidgets('the list shows the athletes by name', (tester) async {
    final repo = FakeAthleteRepository(
      athletesList: const [
        AthleteSummary(id: 'a1', userId: 'u1', name: 'Andi'),
        AthleteSummary(id: 'a2', userId: 'u2', name: 'Ari'),
      ],
    );
    await pumpAthletePage(tester, const AthletesPage(basePath: '/x'), repo);
    expect(find.text('Andi'), findsOneWidget);
    expect(find.byKey(const Key('athlete-a2')), findsOneWidget);
    expect(repo.calls, ['athletes:c1']);
  });

  testWidgets('the list shows the backend error', (tester) async {
    final repo = FakeAthleteRepository(
      failure: const ErrorDeApi('Sin permiso.', estado: 403),
    );
    await pumpAthletePage(tester, const AthletesPage(basePath: '/x'), repo);
    expect(find.text('Sin permiso.'), findsOneWidget);
  });

  testWidgets(
    'the sheet marks the RM in force and shows the factor, its history and the fixed weight',
    (tester) async {
      final repo = FakeAthleteRepository(
        sheets: {
          'a1': AthleteSheet(
            athleteId: 'a1',
            references: [
              rm('r1', 'sq', 100, DateTime.utc(2026, 1, 1)),
              rm('r2', 'sq', 120, DateTime.utc(2026, 10, 1)),
            ],
            factors: [
              factor('f1', 'sq', 90, DateTime.utc(2026, 10, 15)),
              factor('f0', 'sq', 80, DateTime.utc(2026, 9, 1)),
            ],
            fixedWeights: [fixed('curl', 12.5)],
          ),
        },
      );
      await pumpAthletePage(
        tester,
        const AthleteSheetPage(athleteId: 'a1'),
        repo,
        exercises: exercises,
      );

      expect(find.text('Sentadilla'), findsOneWidget);
      expect(find.text('Curl con mancuernas'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('rm-r2')),
          matching: find.text('Vigente'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('rm-r1')),
          matching: find.text('Vigente'),
        ),
        findsNothing,
      );
      expect(find.text('120 kg'), findsOneWidget);
      expect(find.text('desde 01/10/2026'), findsOneWidget);
      expect(find.text('Vigente: 90 %'), findsOneWidget);
      expect(find.text('80 % desde 01/09/2026'), findsOneWidget);
      expect(find.text('12.5 kg'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    },
  );

  testWidgets('an athlete with nothing loaded shows the empty state', (
    tester,
  ) async {
    final repo = FakeAthleteRepository(
      sheets: {'a1': const AthleteSheet(athleteId: 'a1')},
    );
    await pumpAthletePage(
      tester,
      const AthleteSheetPage(athleteId: 'a1'),
      repo,
    );
    expect(find.byKey(const Key('sheet-empty')), findsOneWidget);
  });

  testWidgets('the sheet shows the backend error', (tester) async {
    final repo = FakeAthleteRepository(
      failure: const ErrorDeApi('No se encontró el atleta.', estado: 404),
    );
    await pumpAthletePage(
      tester,
      const AthleteSheetPage(athleteId: 'a1'),
      repo,
    );
    expect(find.text('No se encontró el atleta.'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('shows a spinner while loading', (tester) async {
    final repo = FakeAthleteRepository(
      sheets: {'a1': const AthleteSheet(athleteId: 'a1')},
    );
    await pumpAthletePage(
      tester,
      const AthleteSheetPage(athleteId: 'a1'),
      repo,
      settle: false,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
