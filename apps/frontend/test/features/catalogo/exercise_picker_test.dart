import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/access/presentation/providers.dart';
import 'package:maktub_frontend/features/catalogo/domain/catalog_repository.dart';
import 'package:maktub_frontend/features/catalogo/domain/exercise_draft.dart';
import 'package:maktub_frontend/features/catalogo/presentation/exercise_picker.dart';
import 'package:maktub_frontend/features/catalogo/presentation/providers.dart';
import 'package:maktub_frontend/features/session/domain/session_manager.dart';
import 'package:maktub_frontend/features/session/presentation/providers.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../access/fakes.dart';

Exercise exercise(
  String id,
  String name, {
  String clubId = 'c1',
  List<String> categories = const ['strength'],
  CatalogStatus status = CatalogStatus.active,
}) => Exercise(
  id: id,
  clubId: clubId,
  name: name,
  categoryIds: categories,
  status: status,
  auditoria: Auditoria(creadoPor: 'u1', creadoEn: DateTime.utc(2026, 11, 7)),
);

/// Serves [all] like the API does for a club: its own and base entries, filtered by the query.
class FakeCatalogRepository implements CatalogRepository {
  FakeCatalogRepository(this.all);

  final List<Exercise> all;
  final calls = <(String, String?, CatalogStatus?)>[];

  @override
  Future<List<Exercise>> exercises(
    String clubId, {
    String? categoryId,
    CatalogStatus? status,
  }) async {
    calls.add((clubId, categoryId, status));
    return [
      for (final e in all)
        if ((categoryId == null || e.categoryIds.contains(categoryId)) &&
            (status == null || e.status == status))
          e,
    ];
  }

  @override
  Future<List<Category>> categories(String clubId) async => const [];

  @override
  Future<List<MuscleGroup>> muscleGroups(String clubId) async => const [];

  @override
  Future<List<MovementPattern>> patterns(String clubId) async => const [];

  @override
  Future<Exercise> createExercise(String clubId, ExerciseDraft draft) =>
      throw UnimplementedError();

  @override
  Future<Exercise> updateExercise(
    String clubId,
    String id,
    ExerciseDraft draft,
  ) => throw UnimplementedError();

  @override
  Future<Exercise> setExerciseStatus(
    String clubId,
    String id,
    CatalogStatus status,
  ) => throw UnimplementedError();

  @override
  Future<DeleteExerciseResult> deleteExercise(String clubId, String id) =>
      throw UnimplementedError();
}

class _SignedIn extends SessionController {
  @override
  SessionStatus build() => SessionStatus.signedIn;
}

void main() {
  final gym = club('c1', 'Gimnasio', TipoClub.club);
  final catalog = [
    exercise('squat', 'Sentadilla', clubId: clubPlataforma),
    exercise('bench', 'Press banca', clubId: clubPlataforma),
    exercise('curl', 'Curl de bíceps', categories: ['accessory']),
    exercise('old', 'Press antiguo', status: CatalogStatus.archived),
    exercise('foreign', 'Press de otro club', clubId: 'c2'),
    exercise('wod', 'Burpee', categories: ['wod']),
  ];

  Future<FakeCatalogRepository> pump(
    WidgetTester tester, {
    String? categoryId,
    List<String> recentIds = const [],
    required ValueChanged<Exercise> onSelected,
  }) async {
    final repo = FakeCatalogRepository(catalog);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionControllerProvider.overrideWith(_SignedIn.new),
          meRepositoryProvider.overrideWithValue(
            FakeMeRepository(
              meWith([
                (gym, {Rol.coach}),
              ]),
            ),
          ),
          catalogRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: TemaMaktub.claro(),
          home: Scaffold(
            body: ExercisePicker(
              categoryId: categoryId,
              recentIds: recentIds,
              onSelected: onSelected,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  List<String> shownNames(WidgetTester tester) => [
    for (final t in tester.widgetList<ListTile>(find.byType(ListTile)))
      ((t.title as Text).data!),
  ];

  testWidgets(
    'shows only the active exercises of the category, base and the club\'s, never another club\'s',
    (tester) async {
      final repo = await pump(
        tester,
        categoryId: 'strength',
        onSelected: (_) {},
      );
      expect(shownNames(tester), ['Sentadilla', 'Press banca']);
      expect(repo.calls.single, ('c1', 'strength', CatalogStatus.active));
    },
  );

  testWidgets('another category shows its own exercises', (tester) async {
    await pump(tester, categoryId: 'accessory', onSelected: (_) {});
    expect(shownNames(tester), ['Curl de bíceps']);
  });

  testWidgets('searches by name ignoring case and accents', (tester) async {
    await pump(tester, categoryId: 'accessory', onSelected: (_) {});
    await tester.enterText(find.byType(TextField), 'BICEPS');
    await tester.pump();
    expect(shownNames(tester), ['Curl de bíceps']);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('No hay ejercicios que coincidan.'), findsOneWidget);
  });

  testWidgets('recent exercises come first, in the order given', (
    tester,
  ) async {
    await pump(
      tester,
      categoryId: 'strength',
      recentIds: ['bench', 'gone'],
      onSelected: (_) {},
    );
    expect(shownNames(tester), ['Press banca', 'Sentadilla']);
  });

  testWidgets('tapping an exercise reports it', (tester) async {
    Exercise? chosen;
    await pump(tester, categoryId: 'strength', onSelected: (e) => chosen = e);
    await tester.tap(find.text('Sentadilla'));
    expect(chosen?.id, 'squat');
  });

  testWidgets('showExercisePicker returns the chosen exercise', (tester) async {
    Exercise? result;
    final repo = FakeCatalogRepository(catalog);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionControllerProvider.overrideWith(_SignedIn.new),
          meRepositoryProvider.overrideWithValue(
            FakeMeRepository(
              meWith([
                (gym, {Rol.coach}),
              ]),
            ),
          ),
          catalogRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: TemaMaktub.claro(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showExercisePicker(
                context,
                categoryId: 'accessory',
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Curl de bíceps'));
    await tester.pumpAndSettle();
    expect(result?.id, 'curl');
    expect(find.byType(ExercisePicker), findsNothing);
  });
}
