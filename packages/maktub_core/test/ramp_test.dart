import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

void main() {
  final equipo = Equipo.estandar;
  const one = [RampAthlete(rm: 100)];

  List<double> ramp(
    List<int> groups,
    double? pct,
    List<RampAthlete> athletes, [
    Equipo? e,
  ]) => rampPercentages(
    groupSizes: groups,
    workPct: pct,
    athletes: athletes,
    equipo: e ?? equipo,
  );

  group('rampPercentages', () {
    test('one athlete: the empty bar, equal steps, then the work %', () {
      // RM 100, work 80 % = 80 kg, 3 steps: 20, 20 + 60/3 = 40, 60 kg -> 20, 40, 60 %.
      expect(ramp([1, 1, 1, 1], 80, one), [20, 40, 60, 80]);
    });

    test('every set of a group repeats the group %, the work block keeps the written %', () {
      expect(ramp([1, 1, 2, 3], 80, one), [20, 40, 60, 60, 80, 80, 80]);
    });

    test(
      'two athletes: lowest % for the bar, average for the intermediates',
      () {
        // RM 100 and 80 at 80 %: targets 80 and 64 kg.
        // i=0: 20 kg -> 20 % and 25 %, min 20.
        // i=1: 40 kg -> 40 %; 20 + 44/3 = 34.667 kg -> 43.333 %; average 41.667 -> 41.7.
        // i=2: 60 kg -> 60 %; 20 + 88/3 = 49.333 kg -> 61.667 %; average 60.833 -> 60.8.
        const two = [RampAthlete(rm: 100), RampAthlete(rm: 80)];
        expect(ramp([1, 1, 1, 1], 80, two), [20, 41.7, 60.8, 80]);
      },
    );

    test('two athletes with two approaches: the bar is the minimum, the middle is the average', () {
      // Targets 80 and 64. i=0: min(20, 25) = 20. i=1: kg 50 -> 50 %; 42 -> 52.5 %; average 51.25 -> 51.3.
      const two = [RampAthlete(rm: 100), RampAthlete(rm: 80)];
      expect(ramp([2, 1, 3], 80, two), [20, 20, 51.3, 80, 80, 80]);
    });

    test('the bar comes from the equipment, not a constant of 20', () {
      final e = Equipo.deUnaBarra(barraKg: 15);
      // 15, 15 + 65/2 = 47.5, 80 kg.
      expect(ramp([1, 1, 1], 80, one, e), [15, 47.5, 80]);
    });

    test('the work factor changes the target and the denominator', () {
      // RM 100 × 80 % factor = 80 kg base; work 75 % = 60 kg. 20 kg -> 25 %, 40 kg -> 50 %.
      expect(
        ramp([1, 1, 1], 75, const [RampAthlete(rm: 100, workFactor: 80)]),
        [25, 50, 75],
      );
    });

    test('a neutral factor of 100 gives the same as no factor', () {
      expect(
        ramp([1, 1, 1], 75, const [RampAthlete(rm: 100, workFactor: 100)]),
        ramp([1, 1, 1], 75, const [RampAthlete(rm: 100)]),
      );
    });

    test('without approaches every set has the work %', () {
      expect(ramp([3], 80, one), [80, 80, 80]);
    });

    test('empty without groups, athletes or a work %', () {
      expect(ramp([], 80, one), isEmpty);
      expect(ramp([1, 1], 80, const []), isEmpty);
      expect(ramp([1, 1], null, one), isEmpty);
      expect(ramp([1, 1], 0, one), isEmpty);
      expect(ramp([3], 80, const []), isEmpty);
    });

    test(
      'athletes without a positive RM are ignored instead of dividing by zero',
      () {
        const mixed = [RampAthlete(rm: 0), RampAthlete(rm: 100)];
        expect(ramp([1, 1, 1, 1], 80, mixed), [20, 40, 60, 80]);
        expect(ramp([1, 1], 80, const [RampAthlete(rm: 0)]), isEmpty);
      },
    );
  });
}
