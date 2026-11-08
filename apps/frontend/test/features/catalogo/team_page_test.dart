import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/catalogo/presentation/team_page.dart';

import 'catalog_admin_fakes.dart';

void main() {
  Future<void> add(WidgetTester tester, String kind, String kg) async {
    await tester.enterText(find.byKey(Key('team-$kind-input')), kg);
    await tester.tap(find.byKey(Key('team-$kind-add')));
    await tester.pump();
  }

  testWidgets('shows the inventory with the loadable weights of the standard', (tester) async {
    await pumpAdminPage(tester, const TeamPage(), FakeCatalogAdminRepository());
    expect(find.text('88 pesos con este equipo'), findsOneWidget);
    expect(find.byKey(const Key('plate-1.25')), findsOneWidget);
    expect(find.byKey(const Key('bar-20')), findsOneWidget);
  });

  testWidgets('adding a weight already listed adds a pair, so the preview keeps working', (tester) async {
    final r = FakeCatalogAdminRepository(team: Equipo.deUnaBarra(paresDiscos: const [10]));
    await pumpAdminPage(tester, const TeamPage(), r);
    expect(find.text('2 pesos con este equipo'), findsOneWidget);

    await add(tester, 'plate', '10');
    expect(find.text('3 pesos con este equipo'), findsOneWidget);
    expect(find.byKey(const Key('plate-10')), findsOneWidget);

    await tester.tap(find.byKey(const Key('team-save')));
    await tester.pumpAndSettle();
    expect(r.calls, ['saveTeam']);
    expect(r.savedTeam!.discos, const [ItemInventario(10, 2)]);
  });

  testWidgets('the steppers change how many pairs there are', (tester) async {
    await pumpAdminPage(
      tester,
      const TeamPage(),
      FakeCatalogAdminRepository(team: Equipo.deUnaBarra(paresDiscos: const [10])),
    );
    final row = find.byKey(const Key('plate-10'));
    await tester.tap(find.descendant(of: row, matching: find.byKey(const Key('cantidad-mas'))));
    await tester.pump();
    await tester.tap(find.descendant(of: row, matching: find.byKey(const Key('cantidad-mas'))));
    await tester.pump();
    expect(find.text('4 pesos con este equipo'), findsOneWidget);
    await tester.tap(find.descendant(of: row, matching: find.byKey(const Key('cantidad-menos'))));
    await tester.pump();
    expect(find.text('3 pesos con este equipo'), findsOneWidget);
  });

  testWidgets('several bars: the preview follows the chosen one and saving sends them all', (tester) async {
    final r = FakeCatalogAdminRepository(team: Equipo.deUnaBarra(paresDiscos: const [10]));
    await pumpAdminPage(tester, const TeamPage(), r);
    await add(tester, 'bar', '15');
    expect(find.byKey(const Key('bar-15')), findsOneWidget);

    await tester.tap(find.byKey(const Key('team-preview-bar-15')));
    await tester.pump();
    final preview = tester.widgetList<Text>(
      find.descendant(of: find.byKey(const Key('team-preview')), matching: find.byType(Text)),
    );
    expect([for (final t in preview) t.data], ['15', '35']);

    await tester.tap(find.byKey(const Key('team-save')));
    await tester.pumpAndSettle();
    expect(r.savedTeam!.barras.map((b) => b.kg), [20, 15]);
  });

  testWidgets('removing the last bar is reported and blocks saving', (tester) async {
    await pumpAdminPage(
      tester,
      const TeamPage(),
      FakeCatalogAdminRepository(team: Equipo.deUnaBarra(paresDiscos: const [10])),
    );
    await tester.tap(find.byKey(const Key('bar-remove-20')));
    await tester.pump();
    expect(find.text('Agregá al menos una barra.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('team-save'))).onPressed, isNull);
    expect(find.byKey(const Key('team-preview')), findsNothing);
  });

  testWidgets('a coach who is not club admin sees the weights but cannot edit', (tester) async {
    await pumpAdminPage(tester, const TeamPage(), FakeCatalogAdminRepository(), roles: {Rol.coach});
    expect(find.text('88 pesos con este equipo'), findsOneWidget);
    expect(find.byKey(const Key('team-save')), findsNothing);
    expect(find.byKey(const Key('team-plate-input')), findsNothing);
    expect(find.byKey(const Key('cantidad-mas')), findsNothing);
  });
}
