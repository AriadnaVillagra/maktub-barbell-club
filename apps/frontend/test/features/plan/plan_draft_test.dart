import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/plan/domain/plan_draft.dart';

import '../wods/fakes.dart';
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

  group('blocks', () {
    PlanDraft withDay() => empty().addModel('A');
    PlanBlock block(String name) => PlanBlock(name: name, categoryId: 'c');
    List<String> names(PlanDraft d, [int day = 0]) => [
      for (final b in d.weekModels[0].days[day].blocks) b.name,
    ];

    test('adds at the end, keeps order and leaves the block as given', () {
      final base = withDay();
      final id = base.weekModels[0].id;
      final d = base.addBlock(id, 0, block('x')).addBlock(id, 0, block('y'));
      expect(names(d), ['x', 'y']);
      expect(d.weekModels[0].days[0].blocks[0].prescriptions, isEmpty);
      expect(
        d.weekModels[0].days[0].blocks[0].executionMode,
        ExecutionMode.sequential,
      );
      expect(d.isDirty, isTrue);
      expect(names(base), isEmpty, reason: 'immutable');
    });

    test('moves, updates and removes, leaving other days untouched', () {
      final base = withDay();
      final id = base.weekModels[0].id;
      var d = base.addDay(id);
      d = d.addBlock(id, 0, block('a')).addBlock(id, 0, block('b'));
      d = d.addBlock(id, 0, block('c')).addBlock(id, 1, block('z'));
      d = d.moveBlock(id, 0, 0, 2);
      expect(names(d), ['b', 'c', 'a']);
      d = d.updateBlock(
        id,
        0,
        1,
        (b) => PlanBlock(name: 'C2', categoryId: 'k', timerId: 't'),
      );
      expect(d.weekModels[0].days[0].blocks[1].timerId, 't');
      d = d.removeBlock(id, 0, 0);
      expect(names(d), ['C2', 'a']);
      expect(names(d, 1), ['z']);
    });

    test('out-of-range operations return the same draft', () {
      final d = withDay();
      final id = d.weekModels[0].id;
      final one = d.addBlock(id, 0, block('a'));
      expect(identical(one.addBlock(id, 5, block('x')), one), isTrue);
      expect(identical(one.addBlock('nope', 0, block('x')), one), isTrue);
      expect(identical(one.removeBlock(id, 0, 3), one), isTrue);
      expect(identical(one.moveBlock(id, 0, 0, 1), one), isTrue);
      expect(identical(one.moveBlock(id, 0, 0, 0), one), isTrue);
      expect(identical(one.updateBlock(id, 0, 2, (b) => b), one), isTrue);
    });
  });

  group('prescriptions', () {
    PlanDraft withBlock() {
      final d = empty().addModel('A');
      return d.addBlock(
        d.weekModels[0].id,
        0,
        PlanBlock(name: 'main', categoryId: 'c'),
      );
    }

    List<Prescription> list(PlanDraft d) =>
        d.weekModels[0].days[0].blocks[0].prescriptions;

    test('adds at the end, removes by index, keeps the block fields', () {
      var d = withBlock();
      final id = d.weekModels[0].id;
      d = d.updateBlock(
        id,
        0,
        0,
        (b) => PlanBlock(name: 'main', categoryId: 'k', timerId: 't'),
      );
      d = d
          .addPrescription(id, 0, 0, const Prescription(exerciseId: 'x'))
          .addPrescription(id, 0, 0, const Prescription(exerciseId: 'y'))
          .addPrescription(id, 0, 0, const Prescription(exerciseId: 'z'));
      expect([for (final p in list(d)) p.exerciseId], ['x', 'y', 'z']);
      d = d.removePrescription(id, 0, 0, 1);
      expect([for (final p in list(d)) p.exerciseId], ['x', 'z']);
      final b = d.weekModels[0].days[0].blocks[0];
      expect((b.name, b.categoryId, b.timerId), ('main', 'k', 't'));
      expect(d.isDirty, isTrue);
      d = d.removePrescription(id, 0, 0, 0).removePrescription(id, 0, 0, 0);
      expect(list(d), isEmpty, reason: 'a block without prescriptions is empty');
    });

    test('out-of-range operations change nothing', () {
      final d = withBlock();
      final id = d.weekModels[0].id;
      expect(list(d.removePrescription(id, 0, 0, 3)), isEmpty);
      expect(
        identical(
          d.addPrescription(id, 0, 4, const Prescription()),
          d,
        ),
        isTrue,
      );
      expect(
        identical(d.addPrescription('nope', 0, 0, const Prescription()), d),
        isTrue,
      );
    });
  });

  group('adding a WoD from the library', () {
    const squat = Prescription(exerciseId: 'squat', sets: [PlanSet(reps: 10)]);
    const plank = Prescription(exerciseId: 'plank', timerId: 'hold');

    (PlanDraft, String) withBlock(PlanBlock block) {
      final d = empty().addModel('A');
      final id = d.weekModels[0].id;
      return (d.addBlock(id, 0, block), id);
    }

    PlanBlock blockOf(PlanDraft d) => d.weekModels[0].days[0].blocks[0];

    test('an empty block takes the timer, the note and the prescriptions', () {
      final (d, id) = withBlock(PlanBlock(name: 'WoD', categoryId: 'wod'));
      final wod = sampleWod(
        description: ' 20 min ',
        timerId: 'amrap',
        prescriptions: [squat, plank],
      );
      final b = blockOf(d.addWod(id, 0, 0, wod));
      expect(b.timerId, 'amrap');
      expect(b.note, '20 min');
      expect(b.prescriptions, [squat, plank]);
      expect((b.name, b.categoryId), ('WoD', 'wod'));
    });

    test('keeps the timer and the note the block already has', () {
      final (d, id) = withBlock(
        PlanBlock(
          name: 'WoD',
          categoryId: 'wod',
          timerId: 'mine',
          note: 'mía',
          prescriptions: const [Prescription(exerciseId: 'press')],
        ),
      );
      final wod = sampleWod(
        description: 'otra',
        timerId: 'amrap',
        prescriptions: [squat],
      );
      final b = blockOf(d.addWod(id, 0, 0, wod));
      expect((b.timerId, b.note), ('mine', 'mía'));
      expect([for (final p in b.prescriptions) p.exerciseId], [
        'press',
        'squat',
      ]);
    });

    test('a blank block note counts as none; a blank description adds none', () {
      final (d, id) = withBlock(
        PlanBlock(name: 'WoD', categoryId: 'wod', note: '  '),
      );
      expect(
        blockOf(d.addWod(id, 0, 0, sampleWod(description: 'desc'))).note,
        'desc',
      );
      expect(
        blockOf(d.addWod(id, 0, 0, sampleWod(description: '  '))).note,
        '  ',
        reason: 'nothing to copy leaves the block as it was',
      );
      final (e, eid) = withBlock(PlanBlock(name: 'WoD', categoryId: 'wod'));
      expect(blockOf(e.addWod(eid, 0, 0, sampleWod())).note, isNull);
    });

    test('adding twice appends both; the draft is dirty and a plain copy', () {
      final (d, id) = withBlock(PlanBlock(name: 'WoD', categoryId: 'wod'));
      final wod = sampleWod(prescriptions: [squat]);
      final twice = d.addWod(id, 0, 0, wod).addWod(id, 0, 0, wod);
      expect(blockOf(twice).prescriptions, hasLength(2));
      expect(twice.isDirty, isTrue);
      // Editing the copy leaves the library's WoD as it was.
      final edited = twice.updatePrescription(
        id,
        0,
        0,
        0,
        const Prescription(exerciseId: 'squat', sets: [PlanSet(reps: 3)]),
      );
      expect(wod.prescriptions.single, squat);
      expect(blockOf(edited).prescriptions[0].sets.single.reps, 3);
    });

    test('an unknown block or day changes nothing', () {
      final (d, id) = withBlock(PlanBlock(name: 'WoD', categoryId: 'wod'));
      final wod = sampleWod(prescriptions: [squat]);
      expect(identical(d.addWod(id, 0, 5, wod), d), isTrue);
      expect(identical(d.addWod(id, 3, 0, wod), d), isTrue);
      expect(identical(d.addWod('nope', 0, 0, wod), d), isTrue);
    });

    test('the block note survives adding and removing prescriptions', () {
      final (d, id) = withBlock(
        PlanBlock(name: 'WoD', categoryId: 'wod', note: 'nota'),
      );
      final next = d
          .addPrescription(id, 0, 0, squat)
          .updatePrescription(id, 0, 0, 0, plank)
          .removePrescription(id, 0, 0, 0);
      expect(blockOf(next).note, 'nota');
    });
  });

  test(
    'the modes of a block survive an edit, toPlan and a JSON round trip',
    () {
      var d = empty().addModel('A');
      final m = d.weekModels[0].id;
      d = d.addBlock(
        m,
        0,
        const PlanBlock(name: 'Accesorios', categoryId: 'x'),
      );
      d = d.updateBlock(
        m,
        0,
        0,
        (b) => PlanBlock(
          name: b.name,
          categoryId: b.categoryId,
          executionMode: ExecutionMode.circuit,
          athleteMode: AthleteMode.turns,
        ),
      );
      final back = Plan.fromJson(d.toPlan().toJson());
      final block = back.weekModels[0].days[0].blocks[0];
      expect(block.executionMode, ExecutionMode.circuit);
      expect(block.athleteMode, AthleteMode.turns);
    },
  );
}
