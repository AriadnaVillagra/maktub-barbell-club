import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

PlanSet _set() => const PlanSet(reps: 3);

/// Squat 3 sets and bench 2 in a sequential block, then a timed block with 2 sets of burpees.
const _day = PlanDay(
  blocks: [
    PlanBlock(
      name: 'Fuerza',
      prescriptions: [
        Prescription(exerciseId: 'squat', sets: [PlanSet(reps: 3), PlanSet(reps: 3), PlanSet(reps: 3)]),
        Prescription(exerciseId: 'bench', sets: [PlanSet(reps: 5), PlanSet(reps: 5)]),
      ],
    ),
    PlanBlock(
      name: 'WoD',
      executionMode: ExecutionMode.timed,
      prescriptions: [
        Prescription(exerciseId: 'burpee', sets: [PlanSet(reps: 10), PlanSet(reps: 10)]),
      ],
    ),
  ],
);

SetPosition _at(int b, int p, int s) => (block: b, prescription: p, set: s);

void main() {
  group('planned sets of a day', () {
    test('counts every set of every prescription, timed blocks included', () {
      expect(plannedSetPositions(_day), hasLength(7));
      expect(plannedSetPositions(_day), contains(_at(1, 0, 1)));
    });

    test('a prescription without exercise has nothing to tick', () {
      final day = PlanDay(
        blocks: [
          PlanBlock(name: 'B', prescriptions: [Prescription(sets: [_set()])]),
        ],
      );
      expect(plannedSetPositions(day), isEmpty);
    });

    test('per-athlete loads and missing % do not change the count', () {
      const day = PlanDay(
        blocks: [
          PlanBlock(
            name: 'B',
            prescriptions: [
              Prescription(
                exerciseId: 'squat',
                sets: [
                  PlanSet(reps: 3, byAthlete: {'ari': AthleteSetLoad(pct: 80, kg: 60)}),
                  PlanSet(),
                ],
              ),
            ],
          ),
        ],
      );
      expect(plannedSetPositions(day), hasLength(2));
    });
  });

  group('progress of a day', () {
    test('none done is pending', () {
      final p = dayProgress(_day, const []);
      expect((p.done, p.total, p.status), (0, 7, DayProgressStatus.pending));
    });

    test('some done is in progress, with the count', () {
      final p = dayProgress(_day, [_at(0, 0, 0), _at(0, 0, 1)]);
      expect((p.done, p.total, p.status), (2, 7, DayProgressStatus.inProgress));
    });

    test('every planned set done is done', () {
      final p = dayProgress(_day, plannedSetPositions(_day));
      expect(p.status, DayProgressStatus.done);
      expect(p, const DayProgress(done: 7, total: 7));
    });

    test('a set done on two dates counts once, and positions off the plan do not count', () {
      final p = dayProgress(_day, [_at(0, 0, 0), _at(0, 0, 0), _at(0, 0, 9), _at(5, 0, 0)]);
      expect((p.done, p.total), (1, 7));
    });

    test('a day without planned sets stays pending', () {
      expect(dayProgress(const PlanDay(), const []).status, DayProgressStatus.pending);
    });
  });

  test('the wire names are stable and unknown ones read as pending', () {
    expect([for (final s in DayProgressStatus.values) s.cable], ['pendiente', 'en_curso', 'hecho']);
    expect(DayProgressStatus.fromCable('hecho'), DayProgressStatus.done);
    expect(DayProgressStatus.fromCable('en_curso'), DayProgressStatus.inProgress);
    expect(DayProgressStatus.fromCable('recuperado'), DayProgressStatus.pending);
    expect(DayProgressStatus.fromCable(null), DayProgressStatus.pending);
  });
}
