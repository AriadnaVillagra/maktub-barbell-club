/// Which reference and work factor are in force on a date. Pure; nothing is written to reset a factor.
library;

import '../modelos/referencias.dart';

/// The percentage a work factor has when none is in force.
const defaultWorkFactor = 100.0;

/// The latest of [references] with `date <= on` for [athleteId], [type] and [exerciseId], or null.
/// [exerciseId] is null for `fc_max` and zones. Ties on the same date go to the one created last.
Reference? currentReference(
  Iterable<Reference> references, {
  required String athleteId,
  String? exerciseId,
  required ReferenceType type,
  required DateTime on,
}) {
  Reference? best;
  for (final r in references) {
    if (r.athleteId != athleteId ||
        r.type != type ||
        r.exerciseId != exerciseId ||
        r.date.isAfter(on)) {
      continue;
    }
    if (best == null ||
        _isLater(
          r.date,
          r.auditoria.creadoEn,
          best.date,
          best.auditoria.creadoEn,
        )) {
      best = r;
    }
  }
  return best;
}

/// The work factor (percent) in force for [athleteId] and [exerciseId] on [on].
///
/// It is the latest factor with `date <= on`, but only if it is not older than the RM in force
/// on that date: a newer RM resets the factor to 100 %. A factor dated the same day as the RM counts.
/// With no RM in force the factor stands (the docs do not say otherwise).
double currentWorkFactor(
  Iterable<WorkFactor> factors,
  Iterable<Reference> references, {
  required String athleteId,
  required String exerciseId,
  required DateTime on,
}) {
  WorkFactor? best;
  for (final f in factors) {
    if (f.athleteId != athleteId ||
        f.exerciseId != exerciseId ||
        f.date.isAfter(on)) {
      continue;
    }
    if (best == null ||
        _isLater(
          f.date,
          f.auditoria.creadoEn,
          best.date,
          best.auditoria.creadoEn,
        )) {
      best = f;
    }
  }
  if (best == null) return defaultWorkFactor;
  final rm = currentReference(
    references,
    athleteId: athleteId,
    exerciseId: exerciseId,
    type: ReferenceType.rm,
    on: on,
  );
  if (rm != null && best.date.isBefore(rm.date)) return defaultWorkFactor;
  return best.value;
}

bool _isLater(
  DateTime date,
  DateTime createdAt,
  DateTime otherDate,
  DateTime otherCreatedAt,
) =>
    date.isAfter(otherDate) ||
    (date == otherDate && !createdAt.isBefore(otherCreatedAt));
