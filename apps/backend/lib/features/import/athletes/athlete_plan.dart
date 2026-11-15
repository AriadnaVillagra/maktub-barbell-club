import 'package:maktub_backend/features/import/athletes/athlete_sheets.dart';
import 'package:maktub_backend/features/import/import_report.dart';
import 'package:maktub_backend/features/import/import_run.dart';
import 'package:maktub_core/maktub_core.dart';

/// The `athletes` section of `tool/importar/ajustes.json`.
class AthleteAdjustments {
  const AthleteAdjustments({this.sameAs = const {}, this.testedRmDates = const {}});

  factory AthleteAdjustments.fromJson(Map<String, dynamic> j) => AthleteAdjustments(
    sameAs: {for (final e in ((j['sameAs'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
    testedRmDates: {for (final d in (j['testedRmDates'] as List? ?? const [])) desdeIsoFecha('$d')},
  );

  /// Sheet athlete id → display name of the club athlete it is, when the names differ (the sheet has
  /// full names, the app the names people go by). Display names only: never emails.
  final Map<String, String> sameAs;

  /// Dates of RMs rows that are the February 2026 test (M1-D4): those RMs get origin `testeado`.
  final Set<DateTime> testedRmDates;
}

/// What the club has today, the input of [planAthleteImport].
class AthleteState {
  const AthleteState({required this.athletes, this.rms = const [], this.fixedWeights = const []});

  /// Athletes of the club (only this club: personal clubs are not involved).
  final List<Atleta> athletes;

  /// `rm` references of the club.
  final List<Reference> rms;

  /// Fixed weights of the club.
  final List<FixedWeight> fixedWeights;
}

/// An RM or fixed weight to write, with the report line it came from.
class Planned<T> {
  const Planned(this.item, this.label);

  final T item;
  final String label;
}

/// What the import of Atletas, RMs and PesosAccesorios has to do.
class AthletePlan {
  AthletePlan._() : report = ImportReport('Atletas, RMs y kilajes');

  final ImportReport report;

  /// Sheet athlete id → club athlete id, for every matched athlete. E8.5 resolves Registro through it.
  final athleteIds = <String, String>{};

  final rmsToCreate = <Planned<Reference>>[];
  final fixedWeightsToCreate = <Planned<FixedWeight>>[];

  /// The club athlete of a sheet athlete id (`atleta` column), or null if it was not matched.
  String? athleteIdFor(String sheetId) => athleteIds[sheetId];
}

/// Compares the sheets with [state] and decides, row by row (pure, no I/O):
///
/// - **Athletes.** Never created (E1.9's alta creates them). A sheet athlete matches the club athlete
///   whose display name is the one `sameAs` gives for its id, else the one with the same name (ignoring
///   case and accents). No match, or more than one, is a problem and its rows are not imported.
/// - **RMs.** One `rm` reference per (athlete, exercise, date), [importedId] `rm-<athlete>-<exercise>-<date>`
///   with sheet ids. An existing reference with that key (imported or loaded in the app) is left alone:
///   unchanged if value and origin agree, else reported as differing. Origin is `testeado` when the date
///   is in `testedRmDates`, otherwise `importado`. Repeated rows: the last one wins, as in the old app.
/// - **Fixed weights.** One per (athlete, exercise), [importedId] `kilaje-<athlete>-<exercise>`. An
///   existing one is never replaced. Repeated rows: the last one wins.
///
/// [exerciseIdFor] resolves sheet exercise ids and basic lift keys (`CatalogPlan.exerciseIdFor`).
AthletePlan planAthleteImport(
  AthleteSheets sheets,
  AthleteState state, {
  required String clubId,
  required String? Function(String sheetId) exerciseIdFor,
  AthleteAdjustments adjustments = const AthleteAdjustments(),
  required DateTime now,
}) {
  final plan = AthletePlan._();
  final report = plan.report;
  report.problems.addAll(sheets.problems);
  report.notes.addAll(sheets.notes);
  final audit = Auditoria.nueva(importAuthor, ahora: now);
  final names = {for (final a in state.athletes) a.id: a.nombreVisible};

  _matchAthletes(plan, sheets.athletes, state.athletes, adjustments);
  final known = {for (final a in sheets.athletes) a.id};

  // Resolves athlete and exercise of a row; null (with the problem recorded) when one is missing.
  (String, String)? resolve(String where, String athlete, String exercise) {
    final athleteId = plan.athleteIdFor(athlete);
    if (athleteId == null) {
      report.problems.add(
        known.contains(athlete)
            ? '$where: el atleta $athlete no está vinculado a ningún atleta del club.'
            : '$where: el atleta $athlete no está en Atletas.',
      );
      return null;
    }
    final exerciseId = exerciseIdFor(exercise);
    if (exerciseId == null) {
      report.problems.add('$where: el ejercicio "$exercise" no está en el catálogo.');
      return null;
    }
    return (athleteId, exerciseId);
  }

  // RMs: the last row of each key wins.
  final rms = <(String, String, DateTime), (SheetRm, String)>{};
  for (final row in sheets.rms) {
    final where = 'RMs línea ${row.line}';
    final ids = resolve(where, row.athlete, row.exercise);
    if (ids == null) continue;
    final key = (ids.$1, ids.$2, row.date);
    final previous = rms[key];
    if (previous != null) {
      report.notes.add(
        '$where repite atleta, ejercicio y fecha de la línea ${previous.$1.line}: queda la última '
        '(${_kg(row.kg)} kg${previous.$1.kg == row.kg ? ', igual' : ' en vez de ${_kg(previous.$1.kg)}'}).',
      );
    }
    rms[key] = (row, where);
  }
  for (final MapEntry(key: (athleteId, exerciseId, date), value: (row, where)) in rms.entries) {
    final origin = adjustments.testedRmDates.contains(date) ? ReferenceOrigin.testeado : ReferenceOrigin.importado;
    final label =
        'RM ${names[athleteId]} · $exerciseId · ${aIsoFecha(date)}: ${_kg(row.kg)} kg, ${origin.cable} ($where)';
    final existing = state.rms.where(
      (r) => r.athleteId == athleteId && r.exerciseId == exerciseId && r.date == date && r.type == ReferenceType.rm,
    );
    if (existing.isNotEmpty) {
      if (existing.any((r) => r.value == row.kg && r.origin == origin)) {
        report.unchanged.add(label);
      } else {
        final there = existing.map((r) => '${_kg(r.value)} kg ${r.origin.cable}').join(', ');
        report.differing.add('$label; en la app: $there.');
      }
      continue;
    }
    plan.rmsToCreate.add(
      Planned(
        Reference(
          id: importedId(clubId, 'rm-${row.athlete}-${row.exercise}-${aIsoFecha(date)}'),
          clubId: clubId,
          athleteId: athleteId,
          exerciseId: exerciseId,
          type: ReferenceType.rm,
          value: row.kg,
          date: date,
          origin: origin,
          auditoria: audit,
        ),
        label,
      ),
    );
    report.created.add(label);
  }

  // Fixed weights: the last row of each key wins.
  final weights = <(String, String), (SheetFixedWeight, String)>{};
  for (final row in sheets.fixedWeights) {
    final where = 'PesosAccesorios línea ${row.line}';
    final ids = resolve(where, row.athlete, row.exercise);
    if (ids == null) continue;
    final previous = weights[ids];
    if (previous != null) {
      report.notes.add(
        '$where repite atleta y ejercicio de la línea ${previous.$1.line}: queda la última '
        '(${_kg(row.kg)} kg${previous.$1.kg == row.kg ? ', igual' : ' en vez de ${_kg(previous.$1.kg)}'}).',
      );
    }
    weights[ids] = (row, where);
  }
  for (final MapEntry(key: (athleteId, exerciseId), value: (row, where)) in weights.entries) {
    final label = 'kilaje ${names[athleteId]} · $exerciseId: ${_kg(row.kg)} kg ($where)';
    final existing = state.fixedWeights.where((w) => w.athleteId == athleteId && w.exerciseId == exerciseId);
    if (existing.isNotEmpty) {
      if (existing.first.kg == row.kg) {
        report.unchanged.add(label);
      } else {
        report.differing.add('$label; en la app: ${_kg(existing.first.kg)} kg.');
      }
      continue;
    }
    plan.fixedWeightsToCreate.add(
      Planned(
        FixedWeight(
          id: importedId(clubId, 'kilaje-${row.athlete}-${row.exercise}'),
          clubId: clubId,
          athleteId: athleteId,
          exerciseId: exerciseId,
          kg: row.kg,
          auditoria: audit,
        ),
        label,
      ),
    );
    report.created.add(label);
  }
  return plan;
}

void _matchAthletes(AthletePlan plan, List<SheetAthlete> rows, List<Atleta> athletes, AthleteAdjustments adjustments) {
  final report = plan.report;
  final taken = <String, String>{};
  for (final row in rows) {
    final label = 'atleta ${row.id} (Atletas línea ${row.line})';
    final alias = adjustments.sameAs[row.id];
    final wanted = _normalize(alias ?? row.name);
    final matches = [
      for (final a in athletes)
        if (_normalize(a.nombreVisible) == wanted) a,
    ];
    if (matches.isEmpty) {
      report.problems.add(
        alias != null
            ? '$label: athletes.sameAs lo da como "$alias" y no hay atleta del club con ese nombre.'
            : '$label: ningún atleta del club se llama como en la planilla; agregalo en athletes.sameAs de los ajustes.',
      );
      continue;
    }
    if (matches.length > 1) {
      report.problems.add('$label: hay ${matches.length} atletas del club con ese nombre.');
      continue;
    }
    final athlete = matches.single;
    if (taken.containsKey(athlete.id)) {
      report.problems.add('$label: el atleta ${athlete.nombreVisible} ya está vinculado a ${taken[athlete.id]}.');
      continue;
    }
    taken[athlete.id] = row.id;
    plan.athleteIds[row.id] = athlete.id;
    report.notes.add('$label → ${athlete.nombreVisible}${alias != null ? ' (por ajuste)' : ''}.');
  }
}

const _accents = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'};

String _normalize(String name) {
  final lower = name.trim().toLowerCase();
  return [for (final ch in lower.split('')) _accents[ch] ?? ch].join().replaceAll(RegExp(r'\s+'), ' ');
}

String _kg(double kg) => kg == kg.roundToDouble() ? kg.toStringAsFixed(0) : '$kg';
