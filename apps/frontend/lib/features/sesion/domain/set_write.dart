import 'package:maktub_core/maktub_core.dart';

/// Whether the athlete changed [record] away from the plan, which is what "back to the plan" undoes.
bool setIsEdited(SetRecord record) =>
    record.manualKg || record.reps != record.target.reps;

/// The kilos a set shows: what was typed or marked stays, so moving the day adjustment never rewrites it. Anything
/// else follows the server's proposal.
double? shownKg(SetRecord? record, ProposedSet? proposed) =>
    record != null && (record.manualKg || record.done)
    ? record.kg
    : proposed?.kg;

/// One write of one set, never the whole day. Built from what the set holds now, so changing one thing keeps the rest.
class SetWrite {
  const SetWrite._({
    required this.athleteId,
    required this.blockIndex,
    required this.prescriptionIndex,
    required this.setIndex,
    required this.adjustment,
    required this.done,
    this.manualKg,
    this.reps,
    this.note,
  });

  /// [adjustment] is the day adjustment in force for the set's exercise.
  factory SetWrite.of(
    SetRecord? current, {
    required String athleteId,
    required int blockIndex,
    required int prescriptionIndex,
    required int setIndex,
    required int adjustment,
  }) => SetWrite._(
    athleteId: athleteId,
    blockIndex: blockIndex,
    prescriptionIndex: prescriptionIndex,
    setIndex: setIndex,
    adjustment: adjustment,
    done: current?.done ?? false,
    manualKg: current != null && current.manualKg ? current.kg : null,
    reps: current?.reps,
  );

  final String athleteId;
  final int blockIndex;
  final int prescriptionIndex;
  final int setIndex;
  final int adjustment;
  final bool done;

  /// The kilos typed by hand; null lets the server compute them.
  final double? manualKg;

  /// Null takes the plan's reps.
  final int? reps;

  /// Null leaves the stored note alone; empty clears it.
  final String? note;

  SetWrite _copy({
    required bool done,
    required double? manualKg,
    required int? reps,
    required String? note,
  }) => SetWrite._(
    athleteId: athleteId,
    blockIndex: blockIndex,
    prescriptionIndex: prescriptionIndex,
    setIndex: setIndex,
    adjustment: adjustment,
    done: done,
    manualKg: manualKg,
    reps: reps,
    note: note,
  );

  SetWrite toggled() =>
      _copy(done: !done, manualKg: manualKg, reps: reps, note: note);

  SetWrite edited({required double? manualKg, required int? reps}) =>
      _copy(done: done, manualKg: manualKg, reps: reps, note: note);

  /// Back to what the plan proposes, keeping whether the set is marked.
  SetWrite restored() =>
      _copy(done: done, manualKg: null, reps: null, note: note);

  SetWrite withNote(String note) =>
      _copy(done: done, manualKg: manualKg, reps: reps, note: note);

  Json toJson() => {
    'atletaId': athleteId,
    'bloque': blockIndex,
    'prescripcion': prescriptionIndex,
    'serie': setIndex,
    'hecha': done,
    'ajuste': adjustment,
    if (manualKg != null) ...{'kilosManual': true, 'kilos': manualKg},
    'reps': ?reps,
    'nota': ?note,
  };
}
