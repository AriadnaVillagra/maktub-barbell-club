import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/catalogo/presentation/team_page.dart';

import 'catalog_admin_fakes.dart';

void main() {
  testWidgets('shows the equipment with the loadable weights of the standard', (
    tester,
  ) async {
    await pumpAdminPage(tester, const TeamPage(), FakeCatalogAdminRepository());
    expect(find.text('88 pesos con este equipo'), findsOneWidget);
    expect(find.byKey(const Key('plate-1.25')), findsOneWidget);
  });

  testWidgets(
    'the preview follows the equipment being edited and saving sends it',
    (tester) async {
      final r = FakeCatalogAdminRepository(
        team: Equipo(barraKg: 20, paresDiscos: const [10]),
      );
      await pumpAdminPage(tester, const TeamPage(), r);
      expect(find.text('2 pesos con este equipo'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('team-plate-input')), '5');
      await tester.tap(find.byKey(const Key('team-plate-add')));
      await tester.pump();
      expect(find.text('4 pesos con este equipo'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('team-bar')), '15');
      await tester.pump();
      final preview = tester.widgetList<Text>(
        find.descendant(
          of: find.byKey(const Key('team-preview')),
          matching: find.byType(Text),
        ),
      );
      expect([for (final t in preview) t.data], ['15', '25', '35', '45']);

      await tester.tap(find.byKey(const Key('team-save')));
      await tester.pumpAndSettle();
      expect(r.calls, ['saveTeam']);
      expect(r.savedTeam!.barraKg, 15);
      expect(r.savedTeam!.paresDiscos, [10, 5]);
    },
  );

  testWidgets('removes a plate and refuses an invalid equipment', (
    tester,
  ) async {
    await pumpAdminPage(
      tester,
      const TeamPage(),
      FakeCatalogAdminRepository(team: Equipo(paresDiscos: const [20, 10])),
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('plate-20')),
        matching: find.byType(Icon),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('plate-20')), findsNothing);
    await tester.enterText(find.byKey(const Key('team-plate-input')), '10');
    await tester.tap(find.byKey(const Key('team-plate-add')));
    await tester.pump();
    expect(find.text('Hay dos pares del mismo peso.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('team-save'))).onPressed,
      isNull,
    );
    expect(find.byKey(const Key('team-preview')), findsNothing);
  });

  testWidgets('an athlete sees the weights but cannot edit', (tester) async {
    await pumpAdminPage(
      tester,
      const TeamPage(),
      FakeCatalogAdminRepository(),
      roles: {Rol.atleta},
    );
    expect(find.text('88 pesos con este equipo'), findsOneWidget);
    expect(find.byKey(const Key('team-save')), findsNothing);
    expect(find.byKey(const Key('team-plate-input')), findsNothing);
    expect(
      tester.widget<TextField>(find.byKey(const Key('team-bar'))).enabled,
      isFalse,
    );
  });
}
