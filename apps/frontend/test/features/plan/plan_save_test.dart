import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/core/red/cliente_api.dart';
import 'package:maktub_frontend/features/plan/data/http_plan_repository.dart';
import 'package:maktub_frontend/features/plan/domain/plan_repository.dart';
import 'package:maktub_frontend/features/plan/presentation/plan_editor_page.dart';
import 'package:maktub_frontend/features/plan/presentation/plan_problem_messages.dart';
import 'package:maktub_frontend/features/plan/presentation/providers.dart';

import '../catalogo/catalog_admin_fakes.dart';
import '../catalogo/catalog_fakes.dart' show ex;
import 'fakes.dart';

final squat = ex('squat', 'Sentadilla', categories: ['primario']);

PlanSet pctSet() => const PlanSet(reps: 5, pct: 70);

WeekModel completeModel(String id, {List<PlanSet>? sets}) => WeekModel(
  id: id,
  name: id.toUpperCase(),
  days: [
    PlanDay(
      blocks: [
        PlanBlock(
          name: 'Fuerza',
          categoryId: 'primario',
          prescriptions: [
            Prescription(exerciseId: 'squat', sets: sets ?? [pctSet()]),
          ],
        ),
      ],
    ),
  ],
);

FakeCatalogAdminRepository catalog() => FakeCatalogAdminRepository(
  categoriesList: [category('primario', 'Primario')],
  exercisesList: [squat],
);

Plan validPlan() => samplePlan(
  models: [completeModel('a'), completeModel('b')],
  assignment: ['a', 'a', 'a', 'a'],
);

void main() {
  late FakePlanRepository repo;

  Future<ProviderContainer> open(WidgetTester tester, Plan plan) async {
    repo = FakePlanRepository(plans: [plan]);
    await pumpPlanPage(
      tester,
      const PlanEditorPage(planId: 'p1', listPath: '/x'),
      repo,
      catalog: catalog(),
    );
    return ProviderScope.containerOf(
      tester.element(find.byType(PlanEditorPage)),
    );
  }

  PlanEditor editor(ProviderContainer c) =>
      c.read(planEditorProvider('p1').notifier);

  VoidCallback? saveAction(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const Key('plan-save'))).onPressed;

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('plan-save')));
    await tester.pumpAndSettle();
  }

  group('saving from the editor', () {
    testWidgets('nothing to save while the draft is clean', (tester) async {
      await open(tester, validPlan());
      expect(saveAction(tester), isNull);
    });

    testWidgets('an invalid plan sends nothing and lists every problem', (
      tester,
    ) async {
      final c = await open(
        tester,
        samplePlan(
          models: [
            WeekModel(
              id: 'a',
              name: 'A',
              days: [
                PlanDay(
                  blocks: [PlanBlock(name: 'Fuerza', categoryId: 'primario')],
                ),
              ],
            ),
          ],
          assignment: ['a', 'a', 'a', ''],
        ),
      );
      editor(c).addDay('a');
      await tester.pumpAndSettle();
      await tapSave(tester);

      expect(repo.saved, isEmpty);
      expect(find.byKey(const Key('plan-problems')), findsOneWidget);
      expect(
        find.text('El plan tiene 3 problemas; no se guardó.'),
        findsOneWidget,
      );
      expect(find.text('Modelo A › Día 1 › Bloque 1 "Fuerza"'), findsOneWidget);
      expect(find.text('El bloque no tiene ejercicios.'), findsOneWidget);
      expect(find.text('Modelo A › Día 2'), findsOneWidget);
      expect(find.text('El día no tiene bloques.'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('plan-problems')),
          matching: find.text('Semana 4'),
        ),
        findsOneWidget,
      );
      // The draft is intact and still unsaved.
      expect(find.byKey(const Key('plan-dirty')), findsOneWidget);
      expect(saveAction(tester), isNotNull);
      expect(editor(c).state.value!.weekModels.single.days, hasLength(2));
    });

    testWidgets('a set without % points at the exercise and the set', (
      tester,
    ) async {
      final c = await open(
        tester,
        samplePlan(
          models: [
            completeModel('a', sets: [pctSet(), const PlanSet(reps: 5)]),
          ],
          assignment: ['a', 'a', 'a', 'a'],
        ),
      );
      editor(c).addModel('B');
      await tester.pumpAndSettle();
      await tapSave(tester);

      expect(repo.saved, isEmpty);
      expect(
        find.text(
          'Modelo A › Día 1 › Bloque 1 "Fuerza" › Sentadilla › Serie 2',
        ),
        findsOneWidget,
      );
      expect(find.text('Falta el % de la serie.'), findsOneWidget);
    });

    testWidgets('a valid plan is sent, shows its id and is no longer dirty', (
      tester,
    ) async {
      final c = await open(tester, validPlan());
      editor(c).assign(1, 'b');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('plan-dirty')), findsOneWidget);
      await tapSave(tester);

      expect(repo.saved, hasLength(1));
      expect(repo.saved.single.weekAssignment, ['a', 'b', 'a', 'a']);
      expect(find.text('Plan guardado · id p1'), findsOneWidget);
      expect(find.byKey(const Key('plan-dirty')), findsNothing);
      expect(find.byKey(const Key('plan-problems')), findsNothing);
      expect(saveAction(tester), isNull);
      expect(editor(c).state.value!.base.auditoria.modificadoPor, 'u1');
      expect(editor(c).state.value!.isDirty, isFalse);
    });

    testWidgets('the server 422 shows its own list, draft intact', (
      tester,
    ) async {
      final c = await open(tester, validPlan());
      repo.saveFailure = const PlanRejected(
        'El plan tiene 1 problema(s); no se guardó.',
        [
          PlanProblem(
            PlanProblemCode.setWithoutPct,
            weekModelIndex: 0,
            dayIndex: 0,
            blockIndex: 0,
            prescriptionIndex: 0,
            setIndex: 0,
          ),
        ],
      );
      editor(c).assign(1, 'b');
      await tester.pumpAndSettle();
      await tapSave(tester);

      expect(repo.saved, hasLength(1));
      expect(
        find.text('El plan tiene 1 problema(s); no se guardó.'),
        findsOneWidget,
      );
      expect(find.text('Falta el % de la serie.'), findsOneWidget);
      expect(
        find.text(
          'Modelo A › Día 1 › Bloque 1 "Fuerza" › Sentadilla › Serie 1',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('plan-dirty')), findsOneWidget);
      expect(find.byKey(const Key('plan-saved')), findsNothing);
    });

    testWidgets(
      'network and permission errors are errors, then a retry saves',
      (tester) async {
        final c = await open(tester, validPlan());
        editor(c).assign(1, 'b');
        await tester.pumpAndSettle();

        repo.saveFailure = const ErrorDeApi(
          'No se pudo conectar con el servidor (x).',
        );
        await tapSave(tester);
        expect(find.byKey(const Key('plan-save-error')), findsOneWidget);
        expect(
          find.text('No se pudo conectar con el servidor (x).'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('plan-saved')), findsNothing);
        expect(find.byKey(const Key('plan-dirty')), findsOneWidget);

        repo.saveFailure = const ErrorDeApi('Sin permiso.', estado: 403);
        await tapSave(tester);
        expect(find.text('Sin permiso.'), findsOneWidget);
        expect(find.byKey(const Key('plan-dirty')), findsOneWidget);

        repo.saveFailure = StateError('boom');
        await tapSave(tester);
        expect(find.text('No se pudo guardar el plan.'), findsOneWidget);

        repo.saveFailure = null;
        await tapSave(tester);
        expect(find.byKey(const Key('plan-save-error')), findsNothing);
        expect(find.text('Plan guardado · id p1'), findsOneWidget);
        expect(repo.saved, hasLength(4));
      },
    );

    testWidgets('the action is disabled while saving, so it is sent once', (
      tester,
    ) async {
      final c = await open(tester, validPlan());
      final gate = Completer<void>();
      repo.saveGate = gate.future;
      editor(c).assign(1, 'b');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('plan-save')));
      await tester.pump();
      expect(saveAction(tester), isNull);
      await tester.tap(find.byKey(const Key('plan-save')), warnIfMissed: false);
      await tester.pump();
      await c.read(planSaveProvider('p1').notifier).save();
      expect(repo.saved, hasLength(1));

      // An edit made while saving survives the answer.
      editor(c).assign(2, 'b');
      gate.complete();
      await tester.pumpAndSettle();
      expect(editor(c).state.value!.assignment, ['a', 'b', 'b', 'a']);
      expect(editor(c).state.value!.isDirty, isTrue);
      expect(saveAction(tester), isNotNull);
    });
  });

  group('problem messages', () {
    test('every code has a Spanish message', () {
      for (final code in PlanProblemCode.values) {
        expect(planProblemMessage(code), isNotEmpty, reason: code.name);
        expect(planProblemMessage(code), endsWith('.'), reason: code.name);
      }
    });

    test('an index outside the plan falls back to numbers', () {
      final line = describePlanProblem(
        const PlanProblem(
          PlanProblemCode.setWithoutReps,
          weekModelIndex: 5,
          dayIndex: 2,
          blockIndex: 1,
          prescriptionIndex: 0,
          setIndex: 3,
        ),
        samplePlan(),
        exerciseName: (_) => null,
      );
      expect(
        line.location,
        'Modelo 6 › Día 3 › Bloque 2 › Ejercicio 1 › Serie 4',
      );
    });
  });

  group('HttpPlanRepository.save', () {
    late http.Request sent;

    HttpPlanRepository repoAnswering(int status, Object body) =>
        HttpPlanRepository(
          ClienteApi(
            base: Uri.parse('http://api.test'),
            cliente: MockClient((request) async {
              sent = request;
              return http.Response(
                jsonEncode(body),
                status,
                headers: {'content-type': 'application/json'},
              );
            }),
          ),
        );

    test('PUTs the full plan and reads the stored one', () async {
      final plan = validPlan();
      final saved = await repoAnswering(200, plan.toJson()).save('c1', plan);
      expect(sent.method, 'PUT');
      expect(sent.url.path, '/clubes/c1/planes/p1');
      expect(jsonDecode(sent.body), plan.toJson());
      expect(saved.id, 'p1');
    });

    test('a 422 becomes PlanRejected with the located problems', () async {
      final repo = repoAnswering(422, {
        'error': 'El plan tiene 2 problema(s); no se guardó.',
        'problemas': [
          {'codigo': 'nameEmpty'},
          {
            'codigo': 'setWithoutPct',
            'modeloSemana': 0,
            'dia': 1,
            'bloque': 0,
            'prescripcion': 2,
            'serie': 1,
          },
          {'codigo': 'assignmentUnknownModel', 'semana': 3},
        ],
      });
      await expectLater(
        repo.save('c1', validPlan()),
        throwsA(
          isA<PlanRejected>()
              .having(
                (e) => e.message,
                'message',
                startsWith('El plan tiene 2'),
              )
              .having((e) => e.problems, 'problems', const [
                PlanProblem(PlanProblemCode.nameEmpty),
                PlanProblem(
                  PlanProblemCode.setWithoutPct,
                  weekModelIndex: 0,
                  dayIndex: 1,
                  blockIndex: 0,
                  prescriptionIndex: 2,
                  setIndex: 1,
                ),
                PlanProblem(
                  PlanProblemCode.assignmentUnknownModel,
                  assignmentIndex: 3,
                ),
              ]),
        ),
      );
    });

    test('other failures and unknown codes stay an ErrorDeApi', () async {
      for (final (status, body) in [
        (403, {'error': 'Sin permiso.'}),
        (404, {'error': 'Plan no encontrado.'}),
        (422, {'error': 'Rechazado.'}),
        (
          422,
          {
            'error': 'Rechazado.',
            'problemas': [
              {'codigo': 'somethingNew'},
            ],
          },
        ),
      ]) {
        await expectLater(
          repoAnswering(status, body).save('c1', validPlan()),
          throwsA(
            isA<ErrorDeApi>()
                .having((e) => e.estado, 'estado', status)
                .having((e) => e.mensaje, 'mensaje', body['error']),
          ),
        );
      }
    });
  });
}
