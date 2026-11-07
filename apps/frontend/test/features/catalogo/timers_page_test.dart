import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/catalogo/presentation/timers_page.dart';

import 'catalog_admin_fakes.dart';

void main() {
  FakeCatalogAdminRepository repo() => FakeCatalogAdminRepository(
    timersList: [
      timer('rest', 'Descanso 90', clubId: clubPlataforma),
      timer(
        'mine',
        'Mi EMOM',
        type: TipoTemporizador.emom,
        work: 60,
        rounds: 10,
      ),
      timer('old', 'Viejo', status: CatalogStatus.archived),
    ],
  );

  Future<void> pick(WidgetTester tester, String id, String item) async {
    await tester.tap(find.byKey(Key('timer-menu-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last);
    await tester.pumpAndSettle();
  }

  testWidgets('base timers are fixed, the club\'s have actions', (
    tester,
  ) async {
    await pumpAdminPage(tester, const TimersPage(), repo());
    expect(find.text('Descanso 90'), findsOneWidget);
    expect(find.byKey(const Key('timer-menu-rest')), findsNothing);
    expect(find.byKey(const Key('timer-menu-mine')), findsOneWidget);
    expect(find.textContaining('EMOM · 10 rondas'), findsOneWidget);
  });

  testWidgets('the coach creates a tabata with a phase preview', (
    tester,
  ) async {
    final r = repo();
    await pumpAdminPage(tester, const TimersPage(), r);
    await tester.tap(find.byKey(const Key('timer-add')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('timer-save')))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const Key('timer-name')), 'Tabata core');
    await tester.tap(find.byKey(const Key('timer-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tabata').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('timer-work')), '20');
    await tester.enterText(find.byKey(const Key('timer-rest')), '10');
    await tester.enterText(find.byKey(const Key('timer-rounds')), '8');
    await tester.pump();
    expect(find.text('15 fases · 03:50 en total'), findsOneWidget);
    await tester.tap(find.byKey(const Key('timer-save')));
    await tester.pumpAndSettle();
    expect(r.calls, ['createTimer:Tabata core:tabata:20:10:8']);
    expect(find.text('Tabata core'), findsOneWidget);
  });

  testWidgets('the coach edits a timer', (tester) async {
    final r = repo();
    await pumpAdminPage(tester, const TimersPage(), r);
    await pick(tester, 'mine', 'Editar');
    await tester.enterText(find.byKey(const Key('timer-name')), 'EMOM largo');
    await tester.enterText(find.byKey(const Key('timer-work')), '45');
    await tester.tap(find.byKey(const Key('timer-save')));
    await tester.pumpAndSettle();
    expect(r.calls, ['updateTimer:mine:EMOM largo:45:activo']);
    expect(find.text('EMOM largo'), findsOneWidget);
  });

  testWidgets('the coach archives, reactivates and deletes timers', (
    tester,
  ) async {
    final r = repo();
    await pumpAdminPage(tester, const TimersPage(), r);
    await pick(tester, 'mine', 'Archivar');
    expect(r.calls.last, 'archiveTimer:mine');
    expect(find.textContaining('Archivado'), findsNWidgets(2));
    await pick(tester, 'old', 'Reactivar');
    expect(r.calls.last, 'updateTimer:old:Viejo:90:activo');
    expect(find.textContaining('Archivado'), findsOneWidget);
    await pick(tester, 'old', 'Borrar');
    await tester.tap(find.widgetWithText(FilledButton, 'Borrar'));
    await tester.pumpAndSettle();
    expect(find.text('Viejo'), findsNothing);
  });

  testWidgets('an athlete only reads', (tester) async {
    await pumpAdminPage(
      tester,
      const TimersPage(),
      repo(),
      roles: {Rol.atleta},
    );
    expect(find.text('Mi EMOM'), findsOneWidget);
    expect(find.byKey(const Key('timer-add')), findsNothing);
    expect(find.byKey(const Key('timer-menu-mine')), findsNothing);
  });
}
