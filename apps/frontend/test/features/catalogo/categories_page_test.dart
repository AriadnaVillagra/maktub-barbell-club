import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/catalogo/presentation/categories_page.dart';

import 'catalog_admin_fakes.dart';

void main() {
  FakeCatalogAdminRepository repo() => FakeCatalogAdminRepository(
    categoriesList: [
      category('strength', 'Fuerza', clubId: clubPlataforma),
      category('mine', 'Movilidad'),
      category('old', 'Antigua', status: CatalogStatus.archived),
    ],
  );

  Future<void> pick(WidgetTester tester, String id, String item) async {
    await tester.tap(find.byKey(Key('category-menu-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last);
    await tester.pumpAndSettle();
  }

  testWidgets('lists base categories fixed and the club\'s with actions', (
    tester,
  ) async {
    await pumpAdminPage(tester, const CategoriesPage(), repo());
    expect(find.text('Fuerza'), findsOneWidget);
    expect(find.byKey(const Key('category-menu-strength')), findsNothing);
    expect(find.byKey(const Key('category-menu-mine')), findsOneWidget);
    expect(find.text('Archivada'), findsOneWidget);
  });

  testWidgets('the coach creates a category', (tester) async {
    final r = repo();
    await pumpAdminPage(tester, const CategoriesPage(), r);
    await tester.tap(find.byKey(const Key('category-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('category-name')),
      'Gimnásticos',
    );
    await tester.tap(find.byKey(const Key('category-save')));
    await tester.pumpAndSettle();
    expect(r.calls, ['createCategory:Gimnásticos']);
    expect(find.text('Gimnásticos'), findsOneWidget);
  });

  testWidgets('the coach renames a category', (tester) async {
    final r = repo();
    await pumpAdminPage(tester, const CategoriesPage(), r);
    await pick(tester, 'mine', 'Renombrar');
    await tester.enterText(
      find.byKey(const Key('category-name')),
      'Flexibilidad',
    );
    await tester.tap(find.byKey(const Key('category-save')));
    await tester.pumpAndSettle();
    expect(r.calls, ['renameCategory:mine:Flexibilidad']);
    expect(find.text('Flexibilidad'), findsOneWidget);
    expect(find.text('Movilidad'), findsNothing);
  });

  testWidgets('the coach archives and reactivates a category', (tester) async {
    final r = repo();
    await pumpAdminPage(tester, const CategoriesPage(), r);
    await pick(tester, 'mine', 'Archivar');
    expect(r.calls.last, 'categoryStatus:mine:archivado');
    expect(find.text('Archivada'), findsNWidgets(2));
    await pick(tester, 'old', 'Reactivar');
    expect(r.calls.last, 'categoryStatus:old:activo');
    expect(find.text('Archivada'), findsOneWidget);
  });

  testWidgets('deleting a used category says it was archived', (tester) async {
    final r = repo()..inUse.add('mine');
    await pumpAdminPage(tester, const CategoriesPage(), r);
    await pick(tester, 'mine', 'Borrar');
    await tester.tap(find.widgetWithText(FilledButton, 'Borrar'));
    await tester.pumpAndSettle();
    expect(
      find.text('La categoría está en uso: quedó archivada.'),
      findsOneWidget,
    );
    expect(find.text('Archivada'), findsNWidgets(2));
  });

  testWidgets('deleting an unused category removes it', (tester) async {
    final r = repo();
    await pumpAdminPage(tester, const CategoriesPage(), r);
    await pick(tester, 'mine', 'Borrar');
    await tester.tap(find.widgetWithText(FilledButton, 'Borrar'));
    await tester.pumpAndSettle();
    expect(find.text('Movilidad'), findsNothing);
  });

  testWidgets('an athlete only reads: no add button and no actions', (
    tester,
  ) async {
    await pumpAdminPage(
      tester,
      const CategoriesPage(),
      repo(),
      roles: {Rol.atleta},
    );
    expect(find.text('Movilidad'), findsOneWidget);
    expect(find.byKey(const Key('category-add')), findsNothing);
    expect(find.byKey(const Key('category-menu-mine')), findsNothing);
  });
}
