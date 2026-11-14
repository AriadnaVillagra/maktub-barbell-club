import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

void main() {
  const both = ['andi', 'ari'];

  GuidedStep step(int p, int s, List<String> athletes) =>
      GuidedStep(prescription: p, set: s, athleteIds: athletes);

  List<GuidedStep> steps(
    List<Map<String, int>> counts, {
    ExecutionMode execution = ExecutionMode.sequential,
    AthleteMode athletes = AthleteMode.simultaneous,
    List<String> athleteIds = both,
  }) => guidedSteps(
    executionMode: execution,
    athleteMode: athletes,
    athleteIds: athleteIds,
    setCounts: counts,
  );

  group('guidedSteps, reference cases (pasosDe)', () {
    test('a primary in turns with two athletes: one step per athlete per set, in their order', () {
      expect(
        steps([
          {'andi': 3, 'ari': 3},
        ], athletes: AthleteMode.turns),
        [
          step(0, 0, ['andi']),
          step(0, 0, ['ari']),
          step(0, 1, ['andi']),
          step(0, 1, ['ari']),
          step(0, 2, ['andi']),
          step(0, 2, ['ari']),
        ],
      );
    });

    test('the order of the turns follows the athletes chosen', () {
      expect(
        steps(
          [
            {'andi': 1, 'ari': 1},
          ],
          athletes: AthleteMode.turns,
          athleteIds: ['ari', 'andi'],
        ),
        [
          step(0, 0, ['ari']),
          step(0, 0, ['andi']),
        ],
      );
    });

    test(
      'accessories in a circuit with different set counts: A1 B1 A2 B2 A3',
      () {
        expect(
          steps([
            {'andi': 3, 'ari': 3},
            {'andi': 2, 'ari': 2},
          ], execution: ExecutionMode.circuit),
          [
            step(0, 0, both),
            step(1, 0, both),
            step(0, 1, both),
            step(1, 1, both),
            step(0, 2, both),
          ],
        );
      },
    );

    test('a circuit in turns alternates athletes inside each exercise of the round', () {
      expect(
        steps(
          [
            {'andi': 2, 'ari': 2},
            {'andi': 1, 'ari': 1},
          ],
          execution: ExecutionMode.circuit,
          athletes: AthleteMode.turns,
        ),
        [
          step(0, 0, ['andi']),
          step(0, 0, ['ari']),
          step(1, 0, ['andi']),
          step(1, 0, ['ari']),
          step(0, 1, ['andi']),
          step(0, 1, ['ari']),
        ],
      );
    });

    test(
      'an athlete without a prescription in their day is not in its steps',
      () {
        final counts = [
          {'andi': 2, 'ari': 2},
          {'andi': 2},
        ];
        expect(steps(counts), [
          step(0, 0, both),
          step(0, 1, both),
          step(1, 0, ['andi']),
          step(1, 1, ['andi']),
        ]);
        expect(steps(counts, athletes: AthleteMode.turns), [
          step(0, 0, ['andi']),
          step(0, 0, ['ari']),
          step(0, 1, ['andi']),
          step(0, 1, ['ari']),
          step(1, 0, ['andi']),
          step(1, 1, ['andi']),
        ]);
      },
    );

    test('a prescription nobody has gives no steps', () {
      expect(
        steps([
          {'andi': 1},
          {'ari': 0},
          {'otro': 3},
        ], execution: ExecutionMode.circuit),
        [
          step(0, 0, ['andi']),
        ],
      );
    });
  });

  group('guidedSteps', () {
    test('a simultaneous step carries only the athletes who have that set', () {
      expect(
        steps([
          {'andi': 3, 'ari': 2},
        ]),
        [
          step(0, 0, both),
          step(0, 1, both),
          step(0, 2, ['andi']),
        ],
      );
    });

    test('in a circuit, set counts can differ per athlete too', () {
      expect(
        steps([
          {'andi': 2, 'ari': 1},
          {'andi': 1, 'ari': 2},
        ], execution: ExecutionMode.circuit),
        [
          step(0, 0, both),
          step(1, 0, both),
          step(0, 1, ['andi']),
          step(1, 1, ['ari']),
        ],
      );
    });

    test('a timed block has no steps', () {
      expect(
        steps([
          {'andi': 3, 'ari': 3},
        ], execution: ExecutionMode.timed),
        isEmpty,
      );
    });

    test('a block without sets, or without athletes, has no steps', () {
      expect(steps([]), isEmpty);
      expect(
        steps([
          {},
          {'andi': 0},
        ]),
        isEmpty,
      );
      expect(
        steps([
          {'andi': 3},
        ], athleteIds: []),
        isEmpty,
      );
    });
  });

  group('pendingSteps', () {
    final counts = [
      {'andi': 4, 'ari': 4},
    ];

    test('with nothing done, everything is pending', () {
      final all = steps(counts);
      expect(pendingSteps(all), all);
    });

    test('from simultaneous to turns halfway: done sets stay done, only the rest is split', () {
      final done = {
        for (final a in both)
          for (var s = 0; s < 2; s++) AthleteSet(a, 0, s),
      };
      expect(pendingSteps(steps(counts), done: done), [
        step(0, 2, both),
        step(0, 3, both),
      ]);
      expect(
        pendingSteps(steps(counts, athletes: AthleteMode.turns), done: done),
        [
          step(0, 2, ['andi']),
          step(0, 2, ['ari']),
          step(0, 3, ['andi']),
          step(0, 3, ['ari']),
        ],
      );
    });

    test(
      'from turns to simultaneous with one athlete ahead regroups what is left',
      () {
        final done = {
          const AthleteSet('andi', 0, 0),
          const AthleteSet('ari', 0, 0),
          const AthleteSet('andi', 0, 1),
        };
        expect(pendingSteps(steps(counts), done: done), [
          step(0, 1, ['ari']),
          step(0, 2, both),
          step(0, 3, both),
        ]);
      },
    );

    test('an athlete who left an exercise is not in its pending steps', () {
      final counts = [
        {'andi': 3, 'ari': 3},
        {'andi': 2, 'ari': 2},
      ];
      final pending = pendingSteps(
        steps(counts, execution: ExecutionMode.circuit),
        done: {const AthleteSet('andi', 0, 0), const AthleteSet('ari', 0, 0)},
        left: {const LeftPrescription('ari', 0)},
      );
      expect(pending, [
        step(1, 0, both),
        step(0, 1, ['andi']),
        step(1, 1, both),
        step(0, 2, ['andi']),
      ]);
    });

    test('a step left without athletes disappears', () {
      final pending = pendingSteps(
        steps(counts, athletes: AthleteMode.turns),
        left: {const LeftPrescription('ari', 0)},
      );
      expect(pending, [
        for (var s = 0; s < 4; s++) step(0, s, ['andi']),
      ]);
      expect(
        pendingSteps(
          steps(counts),
          left: {
            const LeftPrescription('andi', 0),
            const LeftPrescription('ari', 0),
          },
        ),
        isEmpty,
      );
    });
  });
}
