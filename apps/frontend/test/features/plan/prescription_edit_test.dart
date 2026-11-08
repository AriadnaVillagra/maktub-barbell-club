import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/plan/domain/plan_draft.dart';
import 'package:maktub_frontend/features/plan/domain/prescription_edit.dart';

import 'fakes.dart';

void main() {
  test('typed numbers accept comma or point and keep zero for E5.9', () {
    expect(parseTypedNumber('72,5'), 72.5);
    expect(parseTypedNumber(' 72.5 '), 72.5);
    expect(parseTypedNumber('0'), 0);
    expect(parseTypedNumber(''), isNull);
    expect(parseTypedNumber('abc'), isNull);
    expect(parseTypedReps('8'), 8);
    expect(parseTypedReps(''), isNull);
  });

  test('setWith replaces reps, % and kg and keeps the other fields', () {
    final s = setWith(
      const PlanSet(reps: 5, maxReps: true, pct: 70, seconds: 30),
      reps: 3,
      pct: null,
      kg: 40,
    );
    expect((s.reps, s.pct, s.kg), (3, null, 40));
    expect((s.maxReps, s.seconds), (true, 30));
  });

  test('addSet copies the last set; removeSet keeps at least one', () {
    const a = PlanSet(reps: 8, pct: 65);
    const b = PlanSet(reps: 5, pct: 72.5);
    final added = addSet(const [a, b]);
    expect(added.length, 3);
    expect(added.last, same(b));
    expect(addSet(const []).length, 1);
    expect(removeSet(const [a, b], 0).single, same(b));
    expect(removeSet(const [a], 0).single, same(a));
    expect(removeSet(const [a, b], 5).length, 2);
  });

  test(
    'prescriptionWith stores a blank note as null and keeps the exercise',
    () {
      const p = Prescription(exerciseId: 'squat', note: 'x', timerId: 't');
      final q = prescriptionWith(
        p,
        sets: const [PlanSet(reps: 1)],
        note: '  ',
        timerId: null,
        barKg: 15,
      );
      expect(
        (q.exerciseId, q.note, q.timerId, q.barKg),
        ('squat', null, null, 15),
      );
      expect(
        prescriptionWith(
          p,
          sets: const [],
          note: ' RPE 8 ',
          timerId: 't',
          barKg: null,
        ).note,
        'RPE 8',
      );
    },
  );

  test('updatePrescription replaces only that prescription', () {
    final draft = PlanDraft.from(
      samplePlan(
        models: [
          WeekModel(
            id: 'a',
            name: 'A',
            days: [
              PlanDay(
                blocks: [
                  PlanBlock(
                    name: 'B',
                    prescriptions: const [
                      Prescription(exerciseId: 'x'),
                      Prescription(exerciseId: 'y'),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
        assignment: ['a', 'a', 'a', 'a'],
      ),
    );
    const edited = Prescription(exerciseId: 'y', note: 'n');
    final next = draft.updatePrescription('a', 0, 0, 1, edited);
    final list = next.modelById('a')!.days[0].blocks[0].prescriptions;
    expect(list[0].exerciseId, 'x');
    expect(list[1].note, 'n');
    expect(next.isDirty, isTrue);
    expect(
      draft
          .updatePrescription('a', 0, 0, 9, edited)
          .modelById('a')!
          .days[0]
          .blocks[0]
          .prescriptions
          .length,
      2,
    );
  });
}
