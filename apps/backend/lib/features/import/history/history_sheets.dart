import 'package:maktub_backend/features/import/sheets.dart';
import 'package:maktub_core/maktub_core.dart';

/// Sheet names and columns of the history (`reference/Esquema.gs` plus what only the live spreadsheet has,
/// design.md D18: `grupo`, `orden` and `modelo` in Registro, and the Tiempos sheet).
abstract final class HistorySheetNames {
  static const records = 'Registro';
  static const times = 'Tiempos';

  static const recordColumns = [
    'fecha',
    'atleta',
    'ejercicio',
    'bloque',
    'serie',
    'peso_kg',
    'reps',
    'rm_vigente',
    'pct',
    'nota',
    'plan',
    'ciclo',
    'semana',
    'dia',
    'grupo',
    'orden',
    'modelo',
  ];
  static const timeColumns = [
    'fecha',
    'plan',
    'ciclo',
    'semana',
    'dia',
    'bloque',
    'atletas',
    'modo',
    'inicio',
    'fin',
    'segundos',
    'interrumpido',
  ];
}

/// Where a row of Registro or Tiempos happened: the old app's session (date, plan, cycle, week and day).
class SheetSessionKey {
  const SheetSessionKey({
    required this.date,
    required this.plan,
    required this.cycle,
    required this.week,
    required this.day,
  });

  final DateTime date;
  final String plan;
  final int cycle;
  final int week;

  /// The PlanDias `dia` number, not an index.
  final int day;

  String get key => '${aIsoFecha(date)}|$plan|$cycle|$week|$day';

  @override
  bool operator ==(Object other) => other is SheetSessionKey && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => '${aIsoFecha(date)} $plan ciclo $cycle semana $week día $day';
}

/// A row of Registro: one set one athlete did (or, without [set], an exercise of a list marked done).
class SheetRecordRow {
  const SheetRecordRow({
    required this.line,
    required this.session,
    required this.athlete,
    required this.exercise,
    required this.block,
    required this.group,
    required this.order,
    required this.variant,
    this.set,
    this.kg,
    this.reps,
    this.rm,
    this.pct,
    this.note,
  });

  final int line;
  final SheetSessionKey session;
  final String athlete;
  final String exercise;

  /// Lowercase, like PlanEjercicios: `estiramiento`, `calentamiento`, `principal`, `final`.
  final String block;
  final String group;
  final int order;

  /// The `modelo` column: the week model (or legacy variant) the set belongs to.
  final String variant;

  /// The sheet's `serie` (1-based), or null for a row without one.
  final int? set;
  final double? kg;

  /// Reps, or seconds for an exercise measured in time (as in PlanEjercicios).
  final int? reps;

  /// `rm_vigente` and `pct` as the old app wrote them; only for checking what the app resolves.
  final double? rm;
  final double? pct;
  final String? note;
}

/// A row of Tiempos: how long one block of a guided session took (D20).
class SheetTimeRow {
  const SheetTimeRow({
    required this.line,
    required this.session,
    required this.block,
    required this.athleteNames,
    required this.mode,
    required this.start,
    required this.end,
    required this.interrupted,
  });

  final int line;
  final SheetSessionKey session;

  /// The old app's block title, such as `Bloque primario: Sentadilla de espalda`.
  final String block;

  /// Display names, as the old app wrote them (it had no ids there).
  final List<String> athleteNames;

  /// `simultaneo`, `turnos`, or null for a block without sets.
  final String? mode;

  /// UTC instants (the sheet keeps them in its own time zone, see [sheetLocalToUtc]).
  final DateTime start;
  final DateTime end;
  final bool interrupted;
}

/// Registro and Tiempos, parsed. Rows that cannot be read go to [problems].
class HistorySheets {
  HistorySheets._();

  factory HistorySheets.read({required Sheet records, required Sheet times}) {
    final out = HistorySheets._();
    for (final row in records.rows) {
      final where = 'Registro línea ${row.line}';
      try {
        final set = _int(row, 'serie');
        out.records.add(
          SheetRecordRow(
            line: row.line,
            session: _session(row),
            athlete: _required(row, 'atleta'),
            exercise: _required(row, 'ejercicio'),
            block: row['bloque'].toLowerCase(),
            group: row['grupo'],
            order: _int(row, 'orden') ?? 0,
            variant: row['modelo'],
            set: set,
            kg: _num(row, 'peso_kg'),
            reps: _int(row, 'reps'),
            rm: _num(row, 'rm_vigente'),
            pct: _num(row, 'pct'),
            note: row.optional('nota'),
          ),
        );
      } on FormatException catch (e) {
        out.problems.add('$where: ${e.message}');
      }
    }
    for (final row in times.rows) {
      final where = 'Tiempos línea ${row.line}';
      try {
        final start = _instant(row, 'inicio');
        final end = _instant(row, 'fin');
        if (end.isBefore(start)) throw const FormatException('"fin" es anterior a "inicio".');
        out.times.add(
          SheetTimeRow(
            line: row.line,
            session: _session(row),
            block: _required(row, 'bloque'),
            athleteNames: [
              for (final n in row['atletas'].split(','))
                if (n.trim().isNotEmpty) n.trim(),
            ],
            mode: row.optional('modo')?.toLowerCase(),
            start: start,
            end: end,
            interrupted: row['interrumpido'].toUpperCase() == 'TRUE',
          ),
        );
      } on FormatException catch (e) {
        out.problems.add('$where: ${e.message}');
      }
    }
    return out;
  }

  final records = <SheetRecordRow>[];
  final times = <SheetTimeRow>[];
  final problems = <String>[];
}

SheetSessionKey _session(SheetRow row) {
  final date = DateTime.tryParse(row['fecha']);
  if (date == null) throw FormatException('fecha "${row['fecha']}" no es una fecha.');
  final cycle = _int(row, 'ciclo'), week = _int(row, 'semana'), day = _int(row, 'dia');
  if (cycle == null || cycle < 1 || week == null || week < 1 || week > planCycleWeeks || day == null || day < 1) {
    throw FormatException('ciclo, semana o día inválidos (${row['ciclo']}, ${row['semana']}, ${row['dia']}).');
  }
  return SheetSessionKey(
    date: DateTime.utc(date.year, date.month, date.day),
    plan: _required(row, 'plan'),
    cycle: cycle,
    week: week,
    day: day,
  );
}

String _required(SheetRow row, String column) {
  final v = row[column];
  if (v.isEmpty) throw FormatException('falta "$column".');
  return v;
}

double? _num(SheetRow row, String column) {
  final v = row[column];
  if (v.isEmpty) return null;
  final n = double.tryParse(v.replaceAll(',', '.'));
  if (n == null || n < 0) throw FormatException('$column "$v" no es un número.');
  return n;
}

int? _int(SheetRow row, String column) {
  final n = _num(row, column);
  if (n == null) return null;
  if (n != n.roundToDouble()) throw FormatException('$column "${row[column]}" no es un entero.');
  return n.toInt();
}

DateTime _instant(SheetRow row, String column) {
  final v = row[column];
  final parsed = DateTime.tryParse(v);
  if (parsed == null) throw FormatException('$column "$v" no es un instante.');
  return parsed.isUtc || RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(v) ? parsed.toUtc() : sheetLocalToUtc(parsed);
}

/// The UTC instant of a wall-clock time of the old spreadsheet, which runs on Europe/Berlin
/// (`reference/appsscript.json`): UTC+1, or UTC+2 from the last Sunday of March at 01:00 UTC to the last
/// Sunday of October at 01:00 UTC (the EU rule). [local]'s fields are read as that wall clock.
DateTime sheetLocalToUtc(DateTime local) {
  final wall = DateTime.utc(
    local.year,
    local.month,
    local.day,
    local.hour,
    local.minute,
    local.second,
    local.millisecond,
  );
  DateTime lastSunday(int month) {
    final last = DateTime.utc(local.year, month + 1, 0);
    return DateTime.utc(local.year, month, last.day - last.weekday % 7, 1);
  }

  final summer = wall.subtract(const Duration(hours: 2));
  final isSummer = !summer.isBefore(lastSunday(3)) && summer.isBefore(lastSunday(10));
  return isSummer ? summer : wall.subtract(const Duration(hours: 1));
}
