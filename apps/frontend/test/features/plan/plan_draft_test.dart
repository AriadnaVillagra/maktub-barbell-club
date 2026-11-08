import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/plan/domain/plan_draft.dart';

import 'fakes.dart';

void main() {
  PlanDraft empty() => PlanDraft.from(samplePlan());

  test('builds the reference shape: models A and B assigned A, B, B, A', () {
    var d = empty().addModel('A').addModel('B');
    final (a, b) = (d.weekModels[0].id, d.weekModels[1].id);
    d = d.assign(0, a).assign(1, b).assign(2, b).assign(3, a);
    d = d.addDay(a).addDay(a); // 3 days
    final plan = d.toPlan();
    expect(plan.weekAssignment, [a, b, b, a]);
    expect(plan.weekModels[0].days, hasLength(3));
    expect(d.isDirty, isTrue);
    expect(
      validatePlan(plan, exerciseById: (_) => null).map((p) => p.code),
      isNot(contains(PlanProblemCode.assignmentUnknownModel)),
    );
  });

  test(
    'a new model starts with one day and ids stay unique after removals',
    () {
      var d = empty().addModel('A').addModel('B');
      expect(d.weekModels[0].days, hasLength(1));
      d = d.removeModel(d.weekModels[0].id).addModel('C');
      expect({for (final m in d.weekModels) m.id}, hasLength(2));
    },
  );

  test('suggests the first free letter', () {
    var d = empty();
    expect(d.suggestedModelName, 'A');
    d = d.addModel('A').addModel('c');
    expect(d.suggestedModelName, 'B');
  });

  test('removing a model unassigns its weeks and keeps the others', () {
    var d = empty().addModel('A').addModel('B');
    final (a, b) = (d.weekModels[0].id, d.weekModels[1].id);
    d = d.assign(0, a).assign(1, b).assign(2, a).assign(3, b).removeModel(a);
    expect(d.assignment, [null, b, null, b]);
  });

  test('assign ignores an unknown model or an out-of-range week', () {
    final d = empty().addModel('A');
    expect(identical(d.assign(0, 'nope'), d), isTrue);
    expect(identical(d.assign(4, d.weekModels[0].id), d), isTrue);
    expect(
      d.assign(0, d.weekModels[0].id).assignment.first,
      d.weekModels[0].id,
    );
  });

  test('days: at most 7, at least 1', () {
    var d = empty().addModel('A');
    final id = d.weekModels[0].id;
    expect(d.canRemoveDay(id), isFalse);
    expect(identical(d.removeDay(id, 0), d), isTrue);
    for (var i = 0; i < 10; i++) {
      d = d.addDay(id);
    }
    expect(d.weekModels[0].days, hasLength(maxDaysPerWeek));
    expect(d.canAddDay(id), isFalse);
    d = d.removeDay(id, 2);
    expect(d.weekModels[0].days, hasLength(6));
  });

  test('moveDay reorders and ignores invalid moves', () {
    final base = PlanDraft.from(
      samplePlan(
        models: [model('x', 'A', 3)],
        assignment: ['x', 'x', 'x', 'x'],
      ),
    );
    List<String?> names(PlanDraft d) => [
      for (final day in d.weekModels[0].days) day.name,
    ];
    expect(names(base.moveDay('x', 0, 2)), ['Dx2', 'Dx3', 'Dx1']);
    expect(names(base.moveDay('x', 2, 1)), ['Dx1', 'Dx3', 'Dx2']);
    expect(identical(base.moveDay('x', 0, 3), base), isTrue);
    expect(identical(base.moveDay('x', 1, 1), base), isTrue);
  });

  test(
    'a plan loaded from the backend is not dirty and keeps its assignment',
    () {
      final d = PlanDraft.from(
        samplePlan(
          models: [model('x', 'A', 2)],
          assignment: ['x', 'x', 'x', 'x'],
        ),
      );
      expect(d.isDirty, isFalse);
      expect(d.assignment, ['x', 'x', 'x', 'x']);
      expect(d.moveDay('x', 0, 1).moveDay('x', 1, 0).isDirty, isFalse);
    },
  );

  test(
    'toPlan turns unassigned weeks into empty ids that validation reports',
    () {
      final plan = empty().addModel('A').toPlan();
      expect(plan.weekAssignment, ['', '', '', '']);
      final codes = validatePlan(
        plan,
        exerciseById: (_) => null,
      ).map((p) => p.code);
      expect(codes, contains(PlanProblemCode.assignmentUnknownModel));
    },
  );
}
