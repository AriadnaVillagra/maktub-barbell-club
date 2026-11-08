import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/access/presentation/providers.dart';
import 'package:maktub_frontend/features/catalogo/presentation/catalog_routes.dart';
import 'package:maktub_frontend/features/catalogo/presentation/providers.dart';
import 'package:maktub_frontend/features/session/domain/session_manager.dart';
import 'package:maktub_frontend/features/session/presentation/providers.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../access/fakes.dart';
import 'catalog_fakes.dart';

class _SignedIn extends SessionController {
  @override
  SessionStatus build() => SessionStatus.signedIn;
}

void main() {
  final gym = club('c1', 'Gimnasio', TipoClub.club);

  late FakeCatalog catalog;

  setUp(() {
    catalog = FakeCatalog([
      ex(
        'squat',
        'Sentadilla',
        clubId: clubPlataforma,
        patternId: 'squat',
        muscles: const [
          MuscleShare(groupId: 'quads', weight: MuscleWeight.primary),
          MuscleShare(groupId: 'glutes', weight: MuscleWeight.secondary),
        ],
      ),
      ex('curl', 'Curl de bíceps', categories: ['accessory']),
      ex('press', 'Press militar'),
      ex('old', 'Press antiguo', status: CatalogStatus.archived),
    ]);
  });

  Future<void> pump(
    WidgetTester tester,
    Set<Rol> roles, {
    String at = '/planificacion/catalogo',
  }) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: at,
      routes: [
        GoRoute(
          path: '/planificacion',
          builder: (_, _) => const SizedBox(),
          routes: [exerciseCatalogRoute()],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionControllerProvider.overrideWith(_SignedIn.new),
          meRepositoryProvider.overrideWithValue(
            FakeMeRepository(meWith([(gym, roles)])),
          ),
          catalogRepositoryProvider.overrideWithValue(catalog),
        ],
        child: MaterialApp.router(
          theme: TemaMaktub.claro(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String> listed(WidgetTester tester) => [
    for (final t in tester.widgetList<ListTile>(find.byType(ListTile)))
      if (t.key.toString().contains('exercise-')) (t.title as Text).data!,
  ];

  group('list', () {
    testWidgets(
      'shows base and own entries with their badge, filters by category and searches',
      (tester) async {
        await pump(tester, {Rol.coach, Rol.adminClub});
        expect(listed(tester), [
          'Curl de bíceps',
          'Press militar',
          'Sentadilla',
        ]);
        expect(find.text('Default'), findsOneWidget);
        expect(find.text('Custom'), findsNWidgets(2));

        await tester.tap(find.widgetWithText(ChoiceChip, 'Accesorio'));
        await tester.pumpAndSettle();
        expect(listed(tester), ['Curl de bíceps']);

        await tester.tap(find.widgetWithText(ChoiceChip, 'Todas'));
        await tester.enterText(find.byType(TextField), 'SENTA');
        await tester.pumpAndSettle();
        expect(listed(tester), ['Sentadilla']);
      },
    );

    testWidgets('the coach can show archived exercises', (tester) async {
      await pump(tester, {Rol.coach, Rol.adminClub});
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(listed(tester), contains('Press antiguo'));
      expect(find.text('Archivado'), findsOneWidget);
    });

    testWidgets('an athlete reads the catalog without edit actions', (
      tester,
    ) async {
      await pump(tester, {Rol.atleta});
      expect(listed(tester), ['Curl de bíceps', 'Press militar', 'Sentadilla']);
      expect(find.byTooltip('Nuevo ejercicio'), findsNothing);
      expect(find.byType(Switch), findsNothing);
    });
  });

  group('detail', () {
    testWidgets(
      'a base exercise is read-only and offers to create an own one',
      (tester) async {
        await pump(tester, {
          Rol.coach, Rol.adminClub,
        }, at: '/planificacion/catalogo/ejercicios/squat');
        expect(find.text('Sentadilla'), findsWidgets);
        expect(find.text('Cuádriceps (100 %), Glúteos (50 %)'), findsOneWidget);
        expect(find.text('Duplicar como custom'), findsOneWidget);
        expect(find.text('Editar'), findsNothing);
        expect(find.text('Archivar'), findsNothing);
      },
    );

    testWidgets('an athlete sees no actions on a base or an own exercise', (
      tester,
    ) async {
      await pump(tester, {
        Rol.atleta,
      }, at: '/planificacion/catalogo/ejercicios/squat');
      expect(find.text('Duplicar como custom'), findsNothing);
      await pump(tester, {
        Rol.atleta,
      }, at: '/planificacion/catalogo/ejercicios/curl');
      expect(find.text('Editar'), findsNothing);
      expect(find.text('Archivar'), findsNothing);
      expect(find.text('Eliminar'), findsNothing);
    });

    testWidgets('"create my own" leaves a club exercise with the same data', (
      tester,
    ) async {
      await pump(tester, {
        Rol.coach, Rol.adminClub,
      }, at: '/planificacion/catalogo/ejercicios/squat');
      await tester.tap(find.text('Duplicar como custom'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextField, 'Sentadilla (custom)'),
        findsOneWidget,
      );
      await tester.tap(find.text('Crear ejercicio'));
      await tester.pumpAndSettle();

      final draft = catalog.created.single;
      final source = catalog.items.firstWhere((e) => e.id == 'squat');
      expect(draft.name, 'Sentadilla (custom)');
      expect(draft.categoryIds, source.categoryIds);
      expect(draft.metrics, source.metrics);
      expect(draft.patternId, 'squat');
      expect(draft.muscles, source.muscles);
      expect(find.text('Custom'), findsOneWidget);
    });
  });

  group('coach writes', () {
    testWidgets(
      'creates an exercise choosing muscles and pattern from the seeded lists',
      (tester) async {
        await pump(tester, {Rol.coach, Rol.adminClub});
        await tester.tap(find.byTooltip('Nuevo ejercicio'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('field-name')),
          '  Zancada ',
        );
        await tester.tap(find.widgetWithText(FilterChip, 'Fuerza'));
        await tester.tap(find.widgetWithText(FilterChip, 'Repeticiones'));
        await tester.tap(find.widgetWithText(FilterChip, 'Carga fija'));
        await tester.tap(find.byKey(const ValueKey('field-pattern')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sentadilla').last);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('muscle-quads')),
            matching: find.text('100 %'),
          ),
        );
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('muscle-glutes')),
            matching: find.text('50 %'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Crear ejercicio'));
        await tester.pumpAndSettle();

        final d = catalog.created.single;
        expect(d.name, 'Zancada');
        expect(d.categoryIds, ['strength']);
        expect(d.metrics, containsAll([Metric.reps, Metric.fixedLoad]));
        expect(d.patternId, 'squat');
        expect(d.muscles, [
          const MuscleShare(groupId: 'quads', weight: MuscleWeight.primary),
          const MuscleShare(groupId: 'glutes', weight: MuscleWeight.secondary),
        ]);
      },
    );

    testWidgets(
      'edits an own exercise and shows the backend error when the name is taken',
      (tester) async {
        await pump(tester, {
          Rol.coach, Rol.adminClub,
        }, at: '/planificacion/catalogo/ejercicios/curl/editar');
        catalog.failWrites = duplicateName;
        await tester.enterText(
          find.byKey(const ValueKey('field-name')),
          'Press militar',
        );
        await tester.tap(find.text('Guardar cambios'));
        await tester.pumpAndSettle();
        expect(
          find.text('Ya hay un ejercicio con ese nombre.'),
          findsOneWidget,
        );
        expect(catalog.updated, isEmpty);

        catalog.failWrites = null;
        await tester.enterText(
          find.byKey(const ValueKey('field-name')),
          'Curl martillo',
        );
        await tester.tap(find.text('Guardar cambios'));
        await tester.pumpAndSettle();
        expect(catalog.updated.single.$1, 'curl');
        expect(catalog.updated.single.$2.name, 'Curl martillo');
        expect(find.text('Curl martillo'), findsWidgets);
      },
    );

    testWidgets('does not send a nameless exercise', (tester) async {
      await pump(tester, {
        Rol.coach, Rol.adminClub,
      }, at: '/planificacion/catalogo/ejercicios/nuevo');
      await tester.tap(find.text('Crear ejercicio'));
      await tester.pumpAndSettle();
      expect(find.text('El nombre es obligatorio.'), findsOneWidget);
      expect(catalog.created, isEmpty);
    });

    testWidgets('archives and restores an own exercise', (tester) async {
      await pump(tester, {
        Rol.coach, Rol.adminClub,
      }, at: '/planificacion/catalogo/ejercicios/curl');
      await tester.tap(find.text('Archivar'));
      await tester.pumpAndSettle();
      expect(catalog.statuses.single, ('curl', CatalogStatus.archived));
      expect(find.text('Restaurar'), findsOneWidget);
      await tester.tap(find.text('Restaurar'));
      await tester.pumpAndSettle();
      expect(catalog.statuses.last, ('curl', CatalogStatus.active));
    });

    testWidgets('deleting one in use reports that it was archived', (
      tester,
    ) async {
      catalog.deleteArchives = true;
      await pump(tester, {
        Rol.coach, Rol.adminClub,
      }, at: '/planificacion/catalogo/ejercicios/curl');
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Eliminar'),
        ),
      );
      await tester.pumpAndSettle();
      expect(catalog.deleted, ['curl']);
      expect(
        find.text('El ejercicio está en uso: se archivó.'),
        findsOneWidget,
      );
    });

    testWidgets('deleting an unused one goes back to the list', (tester) async {
      await pump(tester, {
        Rol.coach, Rol.adminClub,
      }, at: '/planificacion/catalogo/ejercicios/curl');
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Eliminar'),
        ),
      );
      await tester.pumpAndSettle();
      expect(listed(tester), ['Press militar', 'Sentadilla']);
    });
  });
}
