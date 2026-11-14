import 'package:maktub_backend/features/import/sheets.dart';
import 'package:maktub_core/maktub_core.dart';

/// Sheet names and columns of athletes, RMs and accessory weights (`reference/Esquema.gs`, HOJAS).
abstract final class AthleteSheetNames {
  static const athletes = 'Atletas';
  static const rms = 'RMs';
  static const fixedWeights = 'PesosAccesorios';

  static const athleteColumns = ['id', 'nombre'];
  static const rmColumns = ['atleta', 'ejercicio', 'kilos', 'fecha'];
  static const fixedWeightColumns = ['atleta', 'ejercicio', 'kilos'];
}

/// A row of Atletas. [id] is what RMs, PesosAccesorios and Registro use in their `atleta` column.
class SheetAthlete {
  const SheetAthlete({required this.id, required this.name, required this.line});

  final String id;
  final String name;
  final int line;
}

/// A row of RMs: the athlete's RM of [exercise] (a sheet exercise id or a basic lift key) from [date].
class SheetRm {
  const SheetRm({
    required this.athlete,
    required this.exercise,
    required this.kg,
    required this.date,
    required this.line,
  });

  final String athlete;
  final String exercise;
  final double kg;
  final DateTime date;
  final int line;
}

/// A row of PesosAccesorios: the athlete's fixed kilos for an accessory.
class SheetFixedWeight {
  const SheetFixedWeight({required this.athlete, required this.exercise, required this.kg, required this.line});

  final String athlete;
  final String exercise;
  final double kg;
  final int line;
}

/// The three sheets, parsed. Rows that cannot be read go to [problems]; rows the old app treated as
/// "no data" (kilos 0 or empty) go to [notes] and are skipped.
class AthleteSheets {
  AthleteSheets._();

  factory AthleteSheets.read({required Sheet athletes, required Sheet rms, required Sheet fixedWeights}) {
    final out = AthleteSheets._();
    final seen = <String, int>{};
    for (final row in athletes.rows) {
      final id = row['id'];
      if (id.isEmpty) {
        out.problems.add('Atletas línea ${row.line}: sin id.');
        continue;
      }
      if (seen.containsKey(id)) {
        out.problems.add('Atletas línea ${row.line}: el id $id ya está en la línea ${seen[id]}.');
        continue;
      }
      seen[id] = row.line;
      out.athletes.add(SheetAthlete(id: id, name: row['nombre'], line: row.line));
    }

    for (final row in rms.rows) {
      final where = 'RMs línea ${row.line}';
      final base = _base(row, where, out);
      if (base == null) continue;
      final date = _date(row['fecha']);
      if (date == null) {
        out.problems.add('$where: fecha "${row['fecha']}" no es yyyy-MM-dd.');
        continue;
      }
      out.rms.add(SheetRm(athlete: base.$1, exercise: base.$2, kg: base.$3, date: date, line: row.line));
    }

    for (final row in fixedWeights.rows) {
      final base = _base(row, 'PesosAccesorios línea ${row.line}', out);
      if (base == null) continue;
      out.fixedWeights.add(SheetFixedWeight(athlete: base.$1, exercise: base.$2, kg: base.$3, line: row.line));
    }
    return out;
  }

  final athletes = <SheetAthlete>[];
  final rms = <SheetRm>[];
  final fixedWeights = <SheetFixedWeight>[];
  final problems = <String>[];
  final notes = <String>[];

  /// Athlete, exercise and kilos of a row, or null (with the reason recorded) when the row is skipped.
  static (String, String, double)? _base(SheetRow row, String where, AthleteSheets out) {
    final athlete = row['atleta'];
    final exercise = row['ejercicio'];
    if (athlete.isEmpty || exercise.isEmpty) {
      out.problems.add('$where: falta el atleta o el ejercicio.');
      return null;
    }
    final kgCell = row['kilos'];
    final kg = parseKilos(kgCell);
    if (kg == null) {
      out.problems.add('$where: kilos "$kgCell" no es un número.');
      return null;
    }
    if (kg == 0) {
      // The old app seeded 0 for "not measured yet" and read empty cells as 0.
      out.notes.add(
        '$where ($athlete, $exercise): kilos en 0 o vacío, la planilla lo usaba como "sin dato"; no se importa.',
      );
      return null;
    }
    if (kg < 0) {
      out.problems.add('$where: kilos negativos ($kgCell).');
      return null;
    }
    return (athlete, exercise.toLowerCase(), kg);
  }

  static final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static DateTime? _date(String cell) {
    if (!_isoDate.hasMatch(cell)) return null;
    try {
      final d = desdeIsoFecha(cell);
      // Rejects dates that roll over, such as 2026-02-30.
      return aIsoFecha(d) == cell ? d : null;
    } on Object {
      return null;
    }
  }
}

/// Kilos as the sheet writes them: `52.5` or `52,5`; empty reads as 0, like the old app.
double? parseKilos(String cell) {
  if (cell.isEmpty) return 0;
  final v = double.tryParse(cell.replaceAll(',', '.'));
  return v == null || !v.isFinite ? null : v;
}
