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

  Future<void> showArchived(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('show-archived')));
    await tester.pumpAndSettle();
  }

  testWidgets('lists everything in one list with its badge; default ones have no actions for a club admin', (
    tester,
  ) async {
    await pumpAdminPage(tester, const CategoriesPage(), repo());
    expect(find.text('Fuerza'), findsOneWidget);
    expect(find.text('Default'), findsNWidgets(2));
    expect(find.text('Custom'), findsNWidgets(2));
    expect(find.byKey(const Key('category-menu-strength')), findsNothing);
    expect(find.byKey(const Key('category-menu-mine')), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
  });

  testWidgets('filters by origin and shows only the archived ones', (tester) async {
    await pumpAdminPage(tester, const CategoriesPage(), repo());
    expect(find.text('Antigua'), findsNothing);
    await tester.tap(find.byKey(const Key('scope-base')));
    await tester.pumpAndSettle();
    expect(find.text('Movilidad'), findsNothing);
    await tester.tap(find.byKey(const Key('scope-all')));
    await tester.pumpAndSettle();
    await showArchived(tester);
    expect(find.text('Antigua'), findsOneWidget);
    expect(find.text('Movilidad'), findsNothing);
  });

  testWidgets('a platform admin edits a default category by tapping it', (tester) async {
    final r = repo();
    await pumpAdminPage(tester, const CategoriesPage(), r, isPlatformAdmin: true);
    await tester.tap(find.text('Fuerza'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('category-name')), 'Básicos');
    await tester.tap(find.byKey(const Key('category-save')));
    await tester.pumpAndSettle();
    expect(r.calls, ['renameCategory:strength:Básicos']);
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
    await tester.tap(find.text('Movilidad'));
    await tester.pumpAndSettle();
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
    expect(find.text('Movilidad'), findsNothing);
    await showArchived(tester);
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
    expect(find.text('Movilidad'), findsNothing);
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
