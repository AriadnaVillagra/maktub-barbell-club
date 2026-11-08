import 'package:maktub_core/maktub_core.dart';

import 'athlete_repository.dart';

/// What the sheet shows for one exercise.
class ExerciseSheetRow {
  const ExerciseSheetRow({
    required this.exerciseId,
    required this.rms,
    required this.currentRm,
    required this.factor,
    required this.factors,
    required this.fixedWeight,
  });

  final String exerciseId;

  /// RM history, newest first.
  final List<Reference> rms;

  /// The RM in force today, one of [rms]; null when none has started yet.
  final Reference? currentRm;

  /// The factor in force today, in percent (100 when none applies or a newer RM reset it).
  final double factor;

  /// Factor history, newest first.
  final List<WorkFactor> factors;
  final FixedWeight? fixedWeight;
}

int _newestFirst(DateTime ad, DateTime ac, DateTime bd, DateTime bc) {
  final byDate = bd.compareTo(ad);
  return byDate != 0 ? byDate : bc.compareTo(ac);
}

/// One row per exercise the athlete has an RM, a factor or a fixed weight for, in the order of
/// [exerciseIds] first-seen (callers sort by name). Other reference types are left out.
List<ExerciseSheetRow> sheetRows(
  AthleteSheet sheet, {
  required DateTime today,
}) {
  final rms = [
    for (final r in sheet.references)
      if (r.type == ReferenceType.rm && r.exerciseId != null) r,
  ];
  final ids = <String>{
    for (final r in rms) r.exerciseId!,
    for (final f in sheet.factors) f.exerciseId,
    for (final k in sheet.fixedWeights) k.exerciseId,
  };
  return [
    for (final id in ids)
      () {
        final history =
            [
              for (final r in rms)
                if (r.exerciseId == id) r,
            ]..sort(
              (a, b) => _newestFirst(
                a.date,
                a.auditoria.creadoEn,
                b.date,
                b.auditoria.creadoEn,
              ),
            );
        final factors =
            [
              for (final f in sheet.factors)
                if (f.exerciseId == id) f,
            ]..sort(
              (a, b) => _newestFirst(
                a.date,
                a.auditoria.creadoEn,
                b.date,
                b.auditoria.creadoEn,
              ),
            );
        return ExerciseSheetRow(
          exerciseId: id,
          rms: history,
          currentRm: currentReference(
            rms,
            athleteId: sheet.athleteId,
            exerciseId: id,
            type: ReferenceType.rm,
            on: today,
          ),
          factor: currentWorkFactor(
            sheet.factors,
            rms,
            athleteId: sheet.athleteId,
            exerciseId: id,
            on: today,
          ),
          factors: factors,
          fixedWeight: sheet.fixedWeights
              .where((k) => k.exerciseId == id)
              .firstOrNull,
        );
      }(),
  ];
}
