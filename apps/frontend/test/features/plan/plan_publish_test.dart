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
import 'package:maktub_frontend/features/plan/domain/plan_draft.dart';
import 'package:maktub_frontend/features/plan/domain/plan_repository.dart';
import 'package:maktub_frontend/features/plan/presentation/plan_editor_page.dart';
import 'package:maktub_frontend/features/plan/presentation/plans_page.dart';
import 'package:maktub_frontend/features/plan/presentation/providers.dart';

import 'fakes.dart';
import 'plan_save_test.dart' show catalog, completeModel, validPlan;

Plan publishedPlan() {
  final plan = validPlan();
  return samplePlan(
    models: plan.weekModels,
    assignment: plan.weekAssignment,
    published: publishedCopyOf(plan),
  );
}

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

  final publishButton = find.byKey(const Key('plan-publish'));

  bool canPublish(WidgetTester tester) =>
      tester.widget<ButtonStyleButton>(publishButton).onPressed != null;

  String status(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('plan-status'))).data!;

  group('PlanDraft keeps the published copy', () {
    test('toPlan and rebasedOn carry it', () {
      final plan = publishedPlan();
      final draft = PlanDraft.from(plan).addModel('C');
      expect(draft.toPlan().published!.toJson(), plan.published!.toJson());
      final saved = Plan.fromJson(draft.toPlan().toJson());
      expect(draft.rebasedOn(saved).toPlan().published, isNotNull);
      expect(PlanDraft.from(plan).toPlan().toJson(), plan.toJson());
    });
  });

  group('status and button in the editor', () {
    testWidgets(
      'a saved complete plan never published is a draft you can publish',
      (tester) async {
        await open(tester, validPlan());

        expect(status(tester), 'Borrador');
        expect(canPublish(tester), isTrue);
      },
    );

    testWidgets('an incomplete plan is a draft with the button blocked', (
      tester,
    ) async {
      await open(
        tester,
        samplePlan(
          models: [completeModel('a')],
          assignment: ['a', 'a', 'a', ''],
        ),
      );

      expect(status(tester), 'Borrador');
      expect(canPublish(tester), isFalse);
    });

    testWidgets('unsaved changes block the button until they are saved', (
      tester,
    ) async {
      final c = await open(tester, validPlan());
      editor(c).assign(1, 'b');
      await tester.pumpAndSettle();
      expect(canPublish(tester), isFalse);

      await tester.tap(find.byKey(const Key('plan-save')));
      await tester.pumpAndSettle();
      expect(canPublish(tester), isTrue);
    });

    testWidgets('a plan equal to its published copy has nothing to publish', (
      tester,
    ) async {
      await open(tester, publishedPlan());

      expect(status(tester), 'Publicado');
      expect(canPublish(tester), isFalse);
    });

    testWidgets(
      'editing a published plan: unpublished changes, then the button',
      (tester) async {
        final c = await open(tester, publishedPlan());
        editor(c).assign(1, 'b');
        await tester.pumpAndSettle();
        expect(canPublish(tester), isFalse);

        await tester.tap(find.byKey(const Key('plan-save')));
        await tester.pumpAndSettle();

        expect(status(tester), 'Publicado con cambios sin publicar');
        expect(canPublish(tester), isTrue);
        // Saving left the published copy alone.
        expect(editor(c).state.value!.base.published!.weekAssignment, [
          'a',
          'a',
          'a',
          'a',
        ]);
        expect(repo.saved.single.published, isNotNull);
      },
    );

    testWidgets('a name-only change is not something to publish', (
      tester,
    ) async {
      // Name and type are not part of the published copy.
      final plan = publishedPlan();
      await open(
        tester,
        samplePlan(
          name: 'Otro nombre',
          models: plan.weekModels,
          assignment: plan.weekAssignment,
          published: plan.published,
        ),
      );

      expect(canPublish(tester), isFalse);
    });
  });

  group('publishing', () {
    testWidgets('publishes, updates the state and keeps the draft', (
      tester,
    ) async {
      final c = await open(tester, validPlan());
      await tester.tap(publishButton);
      await tester.pumpAndSettle();

      expect(repo.published, ['p1']);
      expect(status(tester), 'Publicado');
      expect(canPublish(tester), isFalse);
      expect(find.byKey(const Key('plan-dirty')), findsNothing);
      final draft = editor(c).state.value!;
      expect(draft.isDirty, isFalse);
      expect(draft.weekModels, hasLength(2));
      expect(draft.base.published, isNotNull);
    });

    testWidgets('an edit made while publishing survives the answer', (
      tester,
    ) async {
      final c = await open(tester, validPlan());
      final gate = Completer<void>();
      repo.publishGate = gate.future;
      await tester.tap(publishButton);
      await tester.pump();

      editor(c).assign(1, 'b');
      gate.complete();
      await tester.pumpAndSettle();

      final draft = editor(c).state.value!;
      expect(draft.assignment, ['a', 'b', 'a', 'a']);
      expect(draft.isDirty, isTrue);
      expect(draft.base.published, isNotNull);
      expect(find.byKey(const Key('plan-dirty')), findsOneWidget);
    });

    testWidgets('cannot publish twice at once', (tester) async {
      final c = await open(tester, validPlan());
      final gate = Completer<void>();
      repo.publishGate = gate.future;
      await tester.tap(publishButton);
      await tester.pump();

      expect(tester.widget<FilledButton>(publishButton).onPressed, isNull);
      await c.read(planPublishProvider('p1').notifier).publish();
      expect(repo.published, hasLength(1));
      gate.complete();
      await tester.pumpAndSettle();
      expect(repo.published, hasLength(1));
    });

    testWidgets('a 422 lists the problems and the draft stays', (tester) async {
      final c = await open(tester, validPlan());
      repo.publishFailure = const PlanRejected(
        'El plan tiene 1 problema(s); no se publicó.',
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
      await tester.tap(publishButton);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('plan-publish-problems')), findsOneWidget);
      expect(
        find.text('El plan tiene 1 problema(s); no se publicó.'),
        findsOneWidget,
      );
      expect(find.text('Falta el % de la serie.'), findsOneWidget);
      expect(status(tester), 'Borrador');
      expect(editor(c).state.value!.base.published, isNull);
      expect(canPublish(tester), isTrue);
    });

    testWidgets('other failures are shown and a retry publishes', (
      tester,
    ) async {
      await open(tester, validPlan());
      repo.publishFailure = const ErrorDeApi('Sin permiso.', estado: 403);
      await tester.tap(publishButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('plan-publish-error')), findsOneWidget);
      expect(find.text('Sin permiso.'), findsOneWidget);

      repo.publishFailure = StateError('boom');
      await tester.tap(publishButton);
      await tester.pumpAndSettle();
      expect(find.text('No se pudo publicar el plan.'), findsOneWidget);

      repo.publishFailure = null;
      await tester.tap(publishButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('plan-publish-error')), findsNothing);
      expect(status(tester), 'Publicado');
    });
  });

  group('plan list', () {
    testWidgets('shows draft, published and published with changes', (
      tester,
    ) async {
      final done = publishedPlan();
      final edited = samplePlan(
        id: 'p3',
        name: 'Editado',
        models: [completeModel('a')],
        assignment: ['a', 'a', 'a', 'a'],
        published: publishedCopyOf(done),
      );
      repo = FakePlanRepository(
        plans: [
          samplePlan(id: 'p1', name: 'Uno'),
          samplePlan(
            id: 'p2',
            name: 'Dos',
            models: done.weekModels,
            assignment: done.weekAssignment,
            published: done.published,
          ),
          edited,
        ],
      );
      await pumpPlanPage(tester, const PlansPage(basePath: '/x'), repo);

      expect(find.text('Regular'), findsNWidgets(3));
      for (final tag in [
        '0 modelos',
        '2 modelos',
        '1 modelo',
        'Borrador',
        'Publicado',
        'Publicado con cambios',
      ]) {
        expect(find.text(tag), findsOneWidget);
      }
    });
  });

  group('HttpPlanRepository.publish', () {
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

    test(
      'POSTs to publicar and reads the plan with its published copy',
      () async {
        final plan = publishedPlan();
        final result = await repoAnswering(
          200,
          plan.toJson(),
        ).publish('c1', 'p1');

        expect(sent.method, 'POST');
        expect(sent.url.path, '/clubes/c1/planes/p1/publicar');
        expect(result.published!.publishedBy, 'u1');
      },
    );

    test('a 422 becomes PlanRejected, a 409 stays an ErrorDeApi', () async {
      await expectLater(
        repoAnswering(422, {
          'error': 'No se publicó.',
          'problemas': [
            {'codigo': 'dayWithoutBlocks', 'modeloSemana': 0, 'dia': 1},
          ],
        }).publish('c1', 'p1'),
        throwsA(
          isA<PlanRejected>().having((e) => e.problems, 'problems', const [
            PlanProblem(
              PlanProblemCode.dayWithoutBlocks,
              weekModelIndex: 0,
              dayIndex: 1,
            ),
          ]),
        ),
      );
      await expectLater(
        repoAnswering(409, {'error': 'Cambió.'}).publish('c1', 'p1'),
        throwsA(isA<ErrorDeApi>().having((e) => e.estado, 'estado', 409)),
      );
    });

    test('the list reads publicado and cambiosSinPublicar', () {
      final s = PlanSummary.fromJson({
        'id': 'p1',
        'nombre': 'X',
        'tipo': 'regular',
        'cantidadModelos': 1,
        'publicado': true,
        'cambiosSinPublicar': false,
      });
      expect(s.published, isTrue);
      expect(s.hasUnpublishedChanges, isFalse);
      final old = PlanSummary.fromJson({'id': 'p1', 'nombre': 'X'});
      expect(old.published, isFalse);
      expect(old.hasUnpublishedChanges, isTrue);
    });
  });
}
