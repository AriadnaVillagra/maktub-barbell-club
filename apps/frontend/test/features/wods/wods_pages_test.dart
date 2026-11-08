import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/wods/domain/wod_repository.dart';
import 'package:maktub_frontend/features/wods/presentation/wod_editor_page.dart';
import 'package:maktub_frontend/features/wods/presentation/wods_page.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../catalogo/catalog_admin_fakes.dart';
import '../catalogo/catalog_fakes.dart' show ex;
import '../plan/fakes.dart';
import 'fakes.dart';

void main() {
  final squat = ex('squat', 'Sentadilla', categories: ['primario']);
  final plank = ex(
    'plank',
    'Plancha',
    categories: ['wod'],
    metrics: const [Metric.time],
  );

  FakeCatalogAdminRepository catalog() => FakeCatalogAdminRepository(
    categoriesList: [category('primario', 'Primario'), category('wod', 'WoD')],
    timersList: [
      timer('amrap', 'AMRAP 12', type: TipoTemporizador.amrap),
      timer('emom', 'EMOM 10', type: TipoTemporizador.emom),
      timer('gone', 'Archivado', status: CatalogStatus.archived),
    ],
    exercisesList: [squat, plank],
  );

  Future<GoRouter> mount(
    WidgetTester tester,
    FakeWodRepository wods, {
    String at = '/wods',
  }) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: at,
      routes: [
        GoRoute(
          path: '/wods',
          builder: (_, _) => const WodsPage(basePath: '/wods'),
          routes: [
            GoRoute(
              path: 'nuevo',
              builder: (_, _) => const WodEditorPage(listPath: '/wods'),
            ),
            GoRoute(
              path: ':id',
              builder: (_, s) => WodEditorPage(
                wodId: s.pathParameters['id']!,
                listPath: '/wods',
              ),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: planOverrides(
          FakePlanRepository(),
          catalog: catalog(),
          wods: wods,
        ),
        child: MaterialApp.router(
          theme: TemaMaktub.claro(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  final fran = sampleWod(
    id: 'w1',
    name: 'Fran',
    timerId: 'amrap',
    prescriptions: const [
      Prescription(exerciseId: 'squat', sets: [PlanSet(reps: 10)]),
      Prescription(exerciseId: 'plank'),
    ],
  );

  group('list', () {
    testWidgets('shows the WoDs by name with their summary', (tester) async {
      await mount(
        tester,
        FakeWodRepository(
          wods: [
            sampleWod(id: 'w2', name: 'Murph'),
            fran,
          ],
        ),
      );
      expect(find.text('Fran'), findsOneWidget);
      expect(
        find.text('2 ejercicios · Temporizador: AMRAP 12'),
        findsOneWidget,
      );
      expect(find.text('0 ejercicios'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Fran')).dy,
        lessThan(tester.getTopLeft(find.text('Murph')).dy),
      );
    });

    testWidgets('has a plain + button and rows without move arrows', (
      tester,
    ) async {
      await mount(tester, FakeWodRepository(wods: [fran]));
      final fab = find.byType(FloatingActionButton);
      expect(tester.widget<FloatingActionButton>(fab).tooltip, 'Nuevo WoD');
      expect(
        find.descendant(of: fab, matching: find.byIcon(Icons.add)),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.arrow_upward), findsNothing);
      expect(find.byIcon(Icons.arrow_downward), findsNothing);
      expect(find.byIcon(Icons.keyboard_arrow_up), findsNothing);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
      // The rows end before the add button's column.
      expect(
        tester.getTopRight(find.byKey(const Key('wod-w1'))).dx,
        lessThan(tester.getTopLeft(fab).dx),
      );
    });

    testWidgets('empty state, loading and backend error', (tester) async {
      await mount(tester, FakeWodRepository());
      expect(find.byKey(const Key('wods-empty')), findsOneWidget);

      await mount(
        tester,
        FakeWodRepository(
          failure: const ErrorDeApi('Sin permiso.', estado: 403),
        ),
      );
      expect(find.text('Sin permiso.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);

      tester.view.physicalSize = const Size(900, 1800);
      await tester.pumpWidget(
        ProviderScope(
          overrides: planOverrides(
            FakePlanRepository(),
            wods: _SlowWodRepository(),
          ),
          child: const MaterialApp(home: WodsPage(basePath: '/wods')),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('deleting asks first and removes the WoD', (tester) async {
      final repo = FakeWodRepository(wods: [fran]);
      await mount(tester, repo);
      await tester.tap(find.byKey(const Key('wod-delete-w1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(repo.calls.where((c) => c.startsWith('delete')), isEmpty);

      await tester.tap(find.byKey(const Key('wod-delete-w1')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Borrar'));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('delete:c1:w1'));
      expect(find.byKey(const Key('wods-empty')), findsOneWidget);
    });

    testWidgets('a failed delete shows the backend message', (tester) async {
      final repo = FakeWodRepository(wods: [fran])
        ..deleteFailure = const ErrorDeApi('No se pudo borrar.', estado: 500);
      await mount(tester, repo);
      await tester.tap(find.byKey(const Key('wod-delete-w1')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Borrar'));
      await tester.pumpAndSettle();
      expect(find.text('No se pudo borrar.'), findsOneWidget);
      expect(find.byKey(const Key('wod-w1')), findsOneWidget);
    });
  });

  group('editor', () {
    Future<void> pick(WidgetTester tester, Key field, String text) async {
      await tester.tap(find.byKey(field));
      await tester.pumpAndSettle();
      await tester.tap(find.text(text).last);
      await tester.pumpAndSettle();
    }

    testWidgets('creates a WoD with timer and exercises of any category', (
      tester,
    ) async {
      final repo = FakeWodRepository();
      await mount(tester, repo);
      await tester.tap(find.byKey(const Key('wod-add')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('wod-name-field')),
        ' Cindy ',
      );
      await tester.enterText(
        find.byKey(const Key('wod-description-field')),
        '20 minutos',
      );
      await pick(tester, const Key('wod-timer-field'), 'EMOM 10');
      expect(find.text('Archivado'), findsNothing);

      // Exercises of two different categories are both offered.
      await tester.tap(find.byKey(const Key('wod-exercise-add')));
      await tester.pumpAndSettle();
      expect(find.text('Sentadilla'), findsOneWidget);
      expect(find.text('Plancha'), findsOneWidget);
      await tester.tap(find.text('Sentadilla'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('wod-exercise-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plancha'));
      await tester.pumpAndSettle();

      // Sets of the first exercise, edited with the plan's prescription dialog.
      await tester.tap(find.byKey(const Key('wod-prescription-0')));
      await tester.pumpAndSettle();
      expect(find.text('El del WoD'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('set-reps-0-0')), '10');
      await tester.tap(find.byKey(const Key('set-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prescription-ok')));
      await tester.pumpAndSettle();
      expect(find.text('2x10'), findsOneWidget);

      await tester.tap(find.byKey(const Key('wod-save')));
      await tester.pumpAndSettle();

      final body = repo.sent.single.toBody();
      expect(body['nombre'], 'Cindy');
      expect(body['descripcion'], '20 minutos');
      expect(body['temporizadorId'], 'emom');
      expect(
        [for (final p in repo.sent.single.prescriptions) p.exerciseId],
        ['squat', 'plank'],
      );
      expect(find.text('Cindy'), findsOneWidget, reason: 'back in the list');
      expect(find.byKey(const Key('wod-name-field')), findsNothing);
    });

    testWidgets('a WoD without name is not sent', (
      tester,
    ) async {
      final repo = FakeWodRepository();
      await mount(tester, repo, at: '/wods/nuevo');
      await tester.tap(find.byKey(const Key('wod-save')));
      await tester.pumpAndSettle();
      expect(find.text('El WoD no tiene nombre.'), findsOneWidget);
      expect(repo.calls.where((c) => c.startsWith('create')), isEmpty);
    });

    testWidgets('shows what the server refused and keeps the form', (
      tester,
    ) async {
      final repo = FakeWodRepository()
        ..writeFailure = const WodRejected('El WoD tiene 1 problema(s).', [
          WodProblem(WodProblemCode.nameEmpty),
        ]);
      await mount(tester, repo, at: '/wods/nuevo');
      await tester.enterText(find.byKey(const Key('wod-name-field')), 'Cindy');
      await tester.tap(find.byKey(const Key('wod-save')));
      await tester.pumpAndSettle();
      expect(find.text('El WoD tiene 1 problema(s).'), findsOneWidget);
      expect(find.text('El WoD no tiene nombre.'), findsOneWidget);
      expect(find.text('Cindy'), findsOneWidget);
    });

    testWidgets('shows a backend error and lets the coach retry', (
      tester,
    ) async {
      final repo = FakeWodRepository()
        ..writeFailure = const ErrorDeApi('Sin permiso.', estado: 403);
      await mount(tester, repo, at: '/wods/nuevo');
      await tester.enterText(find.byKey(const Key('wod-name-field')), 'Cindy');
      await tester.tap(find.byKey(const Key('wod-save')));
      await tester.pumpAndSettle();
      expect(find.text('Sin permiso.'), findsOneWidget);

      repo.writeFailure = null;
      await tester.tap(find.byKey(const Key('wod-save')));
      await tester.pumpAndSettle();
      expect(repo.stored.values.single.name, 'Cindy');
    });

    testWidgets('edits an existing WoD and removes one of its exercises', (
      tester,
    ) async {
      final repo = FakeWodRepository(wods: [fran]);
      await mount(tester, repo);
      await tester.tap(find.byKey(const Key('wod-w1')));
      await tester.pumpAndSettle();
      expect(find.text('Sentadilla'), findsOneWidget);
      expect(find.text('1x10'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('wod-name-field')), 'Fran 2');
      await tester.tap(find.byKey(const Key('wod-prescription-remove-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('wod-save')));
      await tester.pumpAndSettle();

      expect(repo.calls, contains('save:c1:w1'));
      final saved = repo.stored['w1']!;
      expect(saved.name, 'Fran 2');
      expect(saved.timerId, 'amrap');
      expect(saved.prescriptions.map((p) => p.exerciseId), ['squat']);
    });

    testWidgets('an unknown WoD id says so', (tester) async {
      await mount(tester, FakeWodRepository(), at: '/wods/nada');
      expect(find.byKey(const Key('wod-missing')), findsOneWidget);
    });
  });
}

class _SlowWodRepository extends FakeWodRepository {
  final _never = Completer<List<Wod>>();

  @override
  Future<List<Wod>> wods(String clubId) => _never.future;
}
