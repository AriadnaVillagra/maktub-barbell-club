/// How far one athlete got through one day of a plan (decision of Ari, 2026-11-21, which replaces the marking of
/// D13): a day is done when the athlete has every planned set of it done, in progress when some, and pending when
/// none. The backend computes it for the calendar (`.../dias?atletaId=`) and the app reads it back.
library;

import '../modelos/cable.dart';
import '../modelos/plan.dart';

/// Where a set sits in a plan day: block, prescription and set, all 0-based, as a `SetRecord` stores them.
typedef SetPosition = ({int block, int prescription, int set});

/// The state of a day for one athlete. The wire name goes in the `estado` of each day of `.../dias`.
enum DayProgressStatus implements ConCable {
  /// No planned set done.
  pending('pendiente'),

  /// Some planned sets done, not all.
  inProgress('en_curso'),

  /// Every planned set done.
  done('hecho');

  const DayProgressStatus(this.cable);
  @override
  final String cable;

  /// Tolerant on purpose: anything unknown reads as [pending], as clients from before `en_curso` did.
  static DayProgressStatus fromCable(Object? v) {
    for (final s in values) {
      if (s.cable == v) return s;
    }
    return pending;
  }
}

/// Done sets out of the planned ones of a day, for one athlete.
class DayProgress {
  const DayProgress({required this.done, required this.total});

  /// Planned sets the athlete has done. Never more than [total].
  final int done;

  /// Planned sets of the day ([plannedSetPositions]).
  final int total;

  /// A day without planned sets stays pending: there is nothing to tick in it.
  DayProgressStatus get status => done == 0
      ? DayProgressStatus.pending
      : done >= total
      ? DayProgressStatus.done
      : DayProgressStatus.inProgress;

  @override
  bool operator ==(Object other) => other is DayProgress && other.done == done && other.total == total;

  @override
  int get hashCode => Object.hash(done, total);

  @override
  String toString() => 'DayProgress($done/$total)';
}

/// Every set of [day] an athlete can tick: each set of each prescription with an exercise, in every block (a timed
/// block's sets too: finishing the block ticks them). Per-athlete loads (`PlanSet.byAthlete`) change no count.
Set<SetPosition> plannedSetPositions(PlanDay day) => {
  for (final (b, block) in day.blocks.indexed)
    for (final (p, prescription) in block.prescriptions.indexed)
      if (prescription.exerciseId != null)
        for (var s = 0; s < prescription.sets.length; s++) (block: b, prescription: p, set: s),
};

/// How much of [day] is done, given the positions an athlete has recorded as done in any of the day's sessions (a
/// day opened on several dates counts the union). Positions the published plan does not have are left out.
DayProgress dayProgress(PlanDay day, Iterable<SetPosition> donePositions) {
  final planned = plannedSetPositions(day);
  return DayProgress(done: planned.intersection(donePositions.toSet()).length, total: planned.length);
}
