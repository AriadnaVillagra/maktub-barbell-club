import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/atletas/domain/athlete_repository.dart';
import 'package:maktub_frontend/features/atletas/presentation/profile_page.dart';

import '../catalogo/catalog_fakes.dart';
import 'fakes.dart';

void main() {
  final exercises = [ex('sq', 'Sentadilla'), ex('curl', 'Curl con mancuernas')];
  const ids = {'c1': 'a1'};

  testWidgets(
    'shows the own RM with its date, the factor and the fixed weight, with no edit controls',
    (tester) async {
      final repo = FakeAthleteRepository(
        sheets: {
          'a1': AthleteSheet(
            athleteId: 'a1',
            references: [rm('r2', 'sq', 120, DateTime.utc(2026, 10, 1))],
            factors: [factor('f1', 'sq', 90, DateTime.utc(2026, 10, 15))],
            fixedWeights: [fixed('curl', 12.5)],
          ),
        },
      );
      // A coach who is also an athlete still gets no edit controls.
      await pumpAthletePage(
        tester,
        const ProfilePage(),
        repo,
        exercises: exercises,
        roles: {Rol.coach, Rol.atleta},
        athleteIds: ids,
      );
      expect(repo.calls, contains('sheet:c1:a1'));
      expect(find.text('Sentadilla'), findsOneWidget);
      expect(find.byKey(const Key('rm-r2')), findsOneWidget);
      expect(find.byKey(const Key('factor-current-sq')), findsOneWidget);
      expect(find.byKey(const Key('fixed-curl')), findsOneWidget);
      expect(find.byKey(const Key('edit-rm')), findsNothing);
      expect(find.byKey(const Key('edit-factor')), findsNothing);
      expect(find.byKey(const Key('edit-fixedWeight')), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    },
  );

  testWidgets('shows an empty state', (tester) async {
    final repo = FakeAthleteRepository(
      sheets: {'a1': const AthleteSheet(athleteId: 'a1')},
    );
    await pumpAthletePage(tester, const ProfilePage(), repo, athleteIds: ids);
    expect(find.byKey(const Key('sheet-empty')), findsOneWidget);
  });

  testWidgets('shows the loading state', (tester) async {
    final repo = FakeAthleteRepository(
      sheets: {'a1': const AthleteSheet(athleteId: 'a1')},
    );
    await pumpAthletePage(
      tester,
      const ProfilePage(),
      repo,
      athleteIds: ids,
      settle: false,
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('shows the backend error', (tester) async {
    final repo = FakeAthleteRepository(
      failure: const ErrorDeApi('Sin permiso.', estado: 403),
    );
    await pumpAthletePage(tester, const ProfilePage(), repo, athleteIds: ids);
    expect(find.text('Sin permiso.'), findsOneWidget);
  });
}
