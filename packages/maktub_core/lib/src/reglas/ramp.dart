/// Percentages of a ramp: empty bar, intermediate warm-up sets, then the work block.
///
/// Pure rule over values. See "Las rampas" in reference/DISENO.md and `rampa_pct` in the old importer.
library;

import 'equipo.dart';

/// An athlete of the group as the ramp sees them: the RM in force and the work factor (percent,
/// 100 = neutral) already resolved.
class RampAthlete {
  const RampAthlete({required this.rm, this.workFactor = 100});

  final double rm;
  final double workFactor;
}

/// The % of every set of a ramp, in order.
///
/// [groupSizes] are the number of sets of each group: all but the last are approaches, the last is the
/// work block. [workPct] is the % written in the plan for the work block. [athletes] are those of the
/// group.
///
/// Each athlete's target is `rm × workFactor × workPct` (the target of [pesoPorPorcentaje], before
/// rounding to loadable). Approach `i` of `n` weighs `bar + (target - bar) × i / n` kg, and its % is
/// that weight over `rm × workFactor`, so it feeds the same formula as any other set. The first approach
/// (the empty bar, `equipo.barraKg`) takes the lowest % among the athletes, so nobody gets extra plates;
/// the intermediate ones take the average. Approach %s are rounded to one decimal; the work block keeps
/// [workPct] as written. Athletes without a positive RM or work factor are ignored.
///
/// Empty with no groups, no athletes, or no positive [workPct]. With no approaches, every set has [workPct].
List<double> rampPercentages({
  required List<int> groupSizes,
  required double? workPct,
  required List<RampAthlete> athletes,
  required Equipo equipo,
}) {
  final pct = workPct;
  final valid = [
    for (final a in athletes)
      if (a.rm > 0 && a.workFactor > 0) a,
  ];
  if (groupSizes.isEmpty || pct == null || pct <= 0 || valid.isEmpty) {
    return const [];
  }

  final work = groupSizes.last;
  final steps = groupSizes.length - 1;
  if (steps == 0) return List.filled(work, pct);

  final bar = equipo.barraKg;
  final result = <double>[];
  for (var i = 0; i < steps; i++) {
    final perAthlete = [
      for (final a in valid)
        () {
          final base = a.rm * a.workFactor / 100;
          final kg = bar + (base * pct / 100 - bar) * i / steps;
          return kg / base * 100;
        }(),
    ];
    final chosen = i == 0
        ? perAthlete.reduce((a, b) => a < b ? a : b)
        : perAthlete.reduce((a, b) => a + b) / perAthlete.length;
    result.addAll(List.filled(groupSizes[i], (chosen * 10).round() / 10));
  }
  return [...result, ...List.filled(work, pct)];
}
