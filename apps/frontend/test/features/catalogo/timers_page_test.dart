import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/catalogo/presentation/timers_page.dart';
import 'package:maktub_frontend/features/temporizador/presentation/controllers/crono_controller.dart';

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

  testWidgets('lists everything with its badge; default ones have no actions for a club admin', (tester) async {
    await pumpAdminPage(tester, const TimersPage(), repo());
    expect(find.text('Descanso 90'), findsOneWidget);
    expect(find.text('Default'), findsNWidgets(2));
    expect(find.byKey(const Key('timer-menu-rest')), findsNothing);
    expect(find.byKey(const Key('timer-menu-mine')), findsOneWidget);
    expect(find.textContaining('EMOM · 10 rondas'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
  });

  testWidgets('a platform admin edits a default timer by tapping it', (tester) async {
    final r = repo();
    await pumpAdminPage(tester, const TimersPage(), r, isPlatformAdmin: true);
    await tester.tap(find.text('Descanso 90'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('timer-work')), '02:00');
    await tester.tap(find.byKey(const Key('timer-save')));
    await tester.pumpAndSettle();
    expect(r.calls, ['updateTimer:rest:Descanso 90:120:activo']);
  });

  testWidgets('the coach creates a tabata with its total time', (tester) async {
    final r = repo();
    await pumpAdminPage(tester, const TimersPage(), r);
    await tester.tap(find.byKey(const Key('timer-add')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const Key('timer-save'))).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('timer-name')), 'Tabata core');
    await tester.tap(find.byKey(const Key('timer-type-tabata')));
    await tester.pumpAndSettle();
    expect(find.text('Tiempo total: 03:50'), findsOneWidget);
    await tester.tap(find.byKey(const Key('timer-save')));
    await tester.pumpAndSettle();
    expect(r.calls, ['createTimer:Tabata core:tabata:20:10:8']);
    expect(find.text('Tabata core'), findsOneWidget);
  });

  testWidgets('EMOM: every and for give the rounds; Death By has no fixed end', (tester) async {
    final r = repo();
    await pumpAdminPage(tester, const TimersPage(), r);
    await tester.tap(find.byKey(const Key('timer-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('timer-name')), 'E');
    await tester.tap(find.byKey(const Key('timer-type-emom')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('timer-work')), '01:30');
    await tester.enterText(find.byKey(const Key('timer-total')), '9');
    await tester.pump();
    expect(find.text('Tiempo total: 09:00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('timer-death-by')));
    await tester.pumpAndSettle();
    expect(find.text('Sin tiempo fijo'), findsOneWidget);
    expect(find.byKey(const Key('timer-total')), findsNothing);
  });

  testWidgets('For Time has no limit by default and takes one with a signal', (tester) async {
    await pumpAdminPage(tester, const TimersPage(), repo());
    await tester.tap(find.byKey(const Key('timer-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('timer-name')), 'F');
    await tester.tap(find.byKey(const Key('timer-type-for_time')));
    await tester.pumpAndSettle();
    expect(find.text('Sin tiempo fijo'), findsOneWidget);
    await tester.tap(find.byKey(const Key('timer-cap-on')));
    await tester.pumpAndSettle();
    expect(find.text('Tiempo total: 10:00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('timer-signal-on')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('timer-signal')), findsOneWidget);
  });

  testWidgets('AMRAP adds several rounds with rest between them', (tester) async {
    await pumpAdminPage(tester, const TimersPage(), repo());
    await tester.tap(find.byKey(const Key('timer-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('timer-name')), 'A');
    await tester.pump();
    expect(find.text('Tiempo total: 10:00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('timer-sets-on')));
    await tester.pumpAndSettle();
    expect(find.text('Tiempo total: 21:00'), findsOneWidget);
  });

  testWidgets('Mix adds, duplicates and repeats blocks', (tester) async {
    final r = repo();
    await pumpAdminPage(tester, const TimersPage(), r);
    await tester.tap(find.byKey(const Key('timer-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('timer-name')), 'Mix');
    await tester.tap(find.byKey(const Key('timer-type-mix')));
    await tester.pumpAndSettle();
    expect(find.text('Agregá al menos un bloque.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('timer-block-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('timer-type-mix')), findsNothing);
    await tester.tap(find.byKey(const Key('timer-save')).last);
    await tester.pumpAndSettle();
    expect(find.text('Tiempo total: 10:00'), findsOneWidget);

    await tester.tap(find.byKey(const Key('timer-block-copy-0')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('timer-rounds')), '2');
    await tester.pump();
    expect(find.text('Tiempo total: 40:00'), findsOneWidget);
  });

  testWidgets('the coach edits a timer by tapping it', (tester) async {
    final r = repo();
    await pumpAdminPage(tester, const TimersPage(), r);
    await tester.tap(find.text('Mi EMOM'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('timer-name')), 'EMOM largo');
    await tester.enterText(find.byKey(const Key('timer-work')), '45');
    await tester.tap(find.byKey(const Key('timer-save')));
    await tester.pumpAndSettle();
    expect(r.calls, ['updateTimer:mine:EMOM largo:45:activo']);
    expect(find.text('EMOM largo'), findsOneWidget);
  });

  testWidgets('the coach archives, reactivates and deletes timers', (tester) async {
    final r = repo();
    await pumpAdminPage(tester, const TimersPage(), r);
    await pick(tester, 'mine', 'Archivar');
    expect(r.calls.last, 'archiveTimer:mine');
    expect(find.text('Mi EMOM'), findsNothing);
    await tester.tap(find.byKey(const Key('show-archived')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Archivado'), findsNWidgets(2));
    await pick(tester, 'old', 'Reactivar');
    expect(r.calls.last, 'updateTimer:old:Viejo:90:activo');
    expect(find.text('Viejo'), findsNothing);
    await pick(tester, 'mine', 'Borrar');
    await tester.tap(find.widgetWithText(FilledButton, 'Borrar'));
    await tester.pumpAndSettle();
    expect(find.text('Mi EMOM'), findsNothing);
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

  testWidgets('anyone starts an active timer from the list; an archived one has no start button', (tester) async {
    await pumpAdminPage(tester, const TimersPage(), repo());
    expect(find.byKey(const Key('timer-start-old')), findsNothing);
    await tester.tap(find.byKey(const Key('timer-start-rest')));
    await tester.pump();
    final container = ProviderScope.containerOf(tester.element(find.byType(TimersPage)));
    expect(container.read(cronoControllerProvider), isNotNull);
    container.read(cronoControllerProvider.notifier).detener();
    await tester.pump();
  });
}
