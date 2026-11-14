import 'package:maktub_backend/features/import/sheets.dart';

/// Sheet names and columns of the plans of the old app (`reference/Esquema.gs` plus PlanModelos and the
/// `secuencia` column of Planes, which only the live spreadsheet has: design.md D18).
abstract final class PlanSheetNames {
  static const plans = 'Planes';
  static const weekModels = 'PlanModelos';
  static const days = 'PlanDias';
  static const sets = 'PlanEjercicios';
  static const wods = 'PlanWods';

  static const planColumns = ['id', 'nombre', 'activo', 'inicio', 'secuencia'];
  static const weekModelColumns = ['plan', 'id', 'nombre', 'archivado'];
  static const dayColumns = ['plan', 'dia', 'primario', 'estiramiento', 'calentamiento'];
  static const setColumns = [
    'plan',
    'dia',
    'bloque',
    'grupo',
    'orden',
    'ejercicio',
    'variante',
    'serie',
    'reps',
    'pct',
    'rpe',
    'temporizador',
  ];
  static const wodColumns = ['plan', 'dia', 'variante', 'wod'];
}

/// A row of PlanModelos.
class SheetWeekModel {
  const SheetWeekModel({required this.id, required this.name, required this.archived});

  final String id;
  final String name;
  final bool archived;
}

/// A row of PlanDias. The stretching and warm-up lists are exercise ids; empty means "the automatic
/// ones of the primary lift" in the old app.
class SheetDay {
  const SheetDay({
    required this.day,
    required this.primary,
    required this.stretching,
    required this.warmUp,
    required this.line,
  });

  final int day;
  final String? primary;
  final List<String> stretching;
  final List<String> warmUp;
  final int line;
}

/// A row of PlanEjercicios: one set of one exercise in one variant (week model) of one day.
class SheetSetRow {
  const SheetSetRow({
    required this.line,
    required this.day,
    required this.block,
    required this.group,
    required this.order,
    required this.exercise,
    required this.variant,
    required this.set,
    this.reps,
    this.pct,
    this.rpe,
    this.timer,
  });

  final int line;
  final int day;

  /// Lowercase: `estiramiento`, `calentamiento`, `principal`, `final` (others are reported).
  final String block;
  final String group;
  final int order;
  final String exercise;

  /// Lowercase id of the week model (`a`, `descarga`...).
  final String variant;
  final int set;

  /// The target in the `reps` column: repetitions, or seconds for an exercise measured in time.
  final int? reps;
  final double? pct;
  final String? rpe;
  final String? timer;

  SheetSetRow withPct(double? value) => SheetSetRow(
    line: line,
    day: day,
    block: block,
    group: group,
    order: order,
    exercise: exercise,
    variant: variant,
    set: set,
    reps: reps,
    pct: value,
    rpe: rpe,
    timer: timer,
  );
}

/// A plan of Planes with everything the other sheets say about it.
class SheetPlan {
  SheetPlan({
    required this.id,
    required this.name,
    required this.active,
    required this.start,
    required this.sequence,
    required this.line,
  });

  final String id;
  final String name;
  final bool active;
  final String? start;

  /// Week model ids of the 4 weeks (`secuencia`); empty in plans older than the column.
  final List<String> sequence;
  final int line;
  final weekModels = <SheetWeekModel>[];
  final days = <SheetDay>[];
  final rows = <SheetSetRow>[];
}

/// The plan sheets, read. Rows that cannot be read go to [problems]; findings go to [notes].
class PlanSheets {
  PlanSheets._();

  factory PlanSheets.read({
    required Sheet plans,
    required Sheet weekModels,
    required Sheet days,
    required Sheet sets,
    required Sheet wods,
  }) {
    final s = PlanSheets._();
    s._readPlans(plans);
    s._readWeekModels(weekModels);
    s._readDays(days);
    s._readSets(sets);
    s._readWods(wods);
    return s;
  }

  final plans = <SheetPlan>[];
  final problems = <String>[];
  final notes = <String>[];

  static const _truthy = {'true', 'si', 'sí', 'verdadero', '1', 'x'};

  SheetPlan? _plan(Sheet sheet, SheetRow r) {
    final id = r['plan'];
    final plan = plans.where((p) => p.id == id).firstOrNull;
    if (plan == null) problems.add('${sheet.name} línea ${r.line}: el plan "$id" no está en Planes.');
    return plan;
  }

  void _readPlans(Sheet sheet) {
    for (final r in sheet.rows) {
      final id = r['id'];
      if (id.isEmpty || r['nombre'].isEmpty) {
        problems.add('${sheet.name} línea ${r.line}: falta id o nombre.');
        continue;
      }
      if (plans.any((p) => p.id == id)) {
        problems.add('${sheet.name} línea ${r.line}: el plan "$id" se repite; vale la primera fila.');
        continue;
      }
      plans.add(
        SheetPlan(
          id: id,
          name: r['nombre'].replaceAll(RegExp(r'\s+'), ' '),
          active: _truthy.contains(r['activo'].toLowerCase()),
          start: r.optional('inicio'),
          sequence: _list(r['secuencia']).map((s) => s.toLowerCase()).toList(),
          line: r.line,
        ),
      );
    }
  }

  void _readWeekModels(Sheet sheet) {
    for (final r in sheet.rows) {
      final plan = _plan(sheet, r);
      if (plan == null) continue;
      final id = r['id'].toLowerCase();
      if (id.isEmpty) {
        problems.add('${sheet.name} línea ${r.line}: falta el id del modelo.');
        continue;
      }
      if (plan.weekModels.any((m) => m.id == id)) {
        problems.add('${sheet.name} línea ${r.line}: el modelo "$id" de ${plan.id} se repite.');
        continue;
      }
      plan.weekModels.add(
        SheetWeekModel(
          id: id,
          name: r.optional('nombre') ?? id.toUpperCase(),
          archived: _truthy.contains(r['archivado'].toLowerCase()),
        ),
      );
    }
  }

  void _readDays(Sheet sheet) {
    for (final r in sheet.rows) {
      final plan = _plan(sheet, r);
      if (plan == null) continue;
      final day = _int(r['dia']);
      if (day == null || day < 1) {
        problems.add('${sheet.name} línea ${r.line}: el día "${r['dia']}" no es un número.');
        continue;
      }
      if (plan.days.any((d) => d.day == day)) {
        problems.add('${sheet.name} línea ${r.line}: el día $day de ${plan.id} se repite.');
        continue;
      }
      plan.days.add(
        SheetDay(
          day: day,
          primary: r.optional('primario'),
          stretching: _list(r['estiramiento']),
          warmUp: _list(r['calentamiento']),
          line: r.line,
        ),
      );
    }
    for (final p in plans) {
      p.days.sort((a, b) => a.day.compareTo(b.day));
    }
  }

  void _readSets(Sheet sheet) {
    for (final r in sheet.rows) {
      final plan = _plan(sheet, r);
      if (plan == null) continue;
      final where = '${sheet.name} línea ${r.line}';
      final day = _int(r['dia']);
      final set = _int(r['serie']);
      final exercise = r['ejercicio'];
      final variant = r['variante'].toLowerCase();
      if (day == null || set == null || exercise.isEmpty || variant.isEmpty) {
        problems.add('$where: falta día, serie, ejercicio o variante.');
        continue;
      }
      final rawReps = r['reps'];
      final reps = _int(rawReps);
      final rawPct = r['pct'];
      final pct = _number(rawPct);
      if ((rawReps.isNotEmpty && reps == null) || (rawPct.isNotEmpty && pct == null)) {
        problems.add('$where ($exercise): reps "$rawReps" o pct "$rawPct" no es un número.');
        continue;
      }
      plan.rows.add(
        SheetSetRow(
          line: r.line,
          day: day,
          block: r['bloque'].toLowerCase(),
          group: r['grupo'],
          order: _int(r['orden']) ?? 0,
          exercise: exercise,
          variant: variant,
          set: set,
          reps: reps,
          pct: pct,
          rpe: _rpe(r.optional('rpe'), '$where ($exercise)'),
          timer: r.optional('temporizador'),
        ),
      );
    }
  }

  void _readWods(Sheet sheet) {
    // PlanWods is empty in the export (E8.4, "Restricciones"). A row is reported instead of guessed, so a
    // later export with WoDs fails loudly rather than losing them.
    for (final r in sheet.rows) {
      problems.add(
        '${sheet.name} línea ${r.line}: el importador no carga WoDs de planes todavía '
        '(${r['plan']}, día ${r['dia']}, ${r['variante']}: ${r['wod']}).',
      );
    }
  }

  /// RPE is free text in the plan (it lands in the prescription note). The spreadsheet turned "6-7" into
  /// a date in one cell (`2026-06-07`): read back as "6 - 7", the way the other cells write it.
  String? _rpe(String? value, String where) {
    if (value == null) return null;
    final date = RegExp(r'^\d{4}-(\d{2})-(\d{2})$').firstMatch(value);
    if (date == null) return value;
    final fixed = '${int.parse(date[1]!)} - ${int.parse(date[2]!)}';
    notes.add('$where: rpe "$value" es un rango que la planilla convirtió en fecha; se lee "$fixed".');
    return fixed;
  }

  static List<String> _list(String cell) => [
    for (final s in cell.split(','))
      if (s.trim().isNotEmpty) s.trim(),
  ];

  static double? _number(String v) => v.isEmpty ? null : double.tryParse(v.replaceAll(',', '.'));

  static int? _int(String v) {
    final n = _number(v);
    return n == null || n != n.roundToDouble() ? null : n.toInt();
  }
}

/// A fix of the plan's percentages decided outside the sheet (`plans.pctCorrections` in the adjustments):
/// M1-D4, October 2026 has 85 % where it should say 80 %.
class PctCorrection {
  const PctCorrection({required this.planId, required this.from, required this.to});

  factory PctCorrection.fromJson(Map<String, dynamic> j) =>
      PctCorrection(planId: '${j['plan']}', from: (j['from'] as num).toDouble(), to: (j['to'] as num).toDouble());

  final String planId;
  final double from;
  final double to;
}

/// Applies [corrections] to the rows of [plan] and returns how many sets changed. In every exercise (of one
/// day and variant) that has sets at `from`, those sets become `to`, and the ramp below them is moved with
/// them: each intermediate set keeps its place between the first set (the empty bar, untouched) and the work
/// percentage, which is how the old app's ramps are built (`reference/DISENO.md`, "Las rampas"). Rounded to
/// 0.1, like the sheet.
int applyPctCorrections(SheetPlan plan, List<PctCorrection> corrections) {
  var changed = 0;
  for (final c in corrections.where((c) => c.planId == plan.id)) {
    final byExercise = <String, List<int>>{};
    for (var i = 0; i < plan.rows.length; i++) {
      final r = plan.rows[i];
      byExercise.putIfAbsent('${r.variant}|${r.day}|${r.block}|${r.group}|${r.order}|${r.exercise}', () => []).add(i);
    }
    for (final indexes in byExercise.values) {
      indexes.sort((a, b) => plan.rows[a].set.compareTo(plan.rows[b].set));
      if (!indexes.any((i) => plan.rows[i].pct == c.from)) continue;
      final bar = plan.rows[indexes.first].pct;
      for (var k = 0; k < indexes.length; k++) {
        final row = plan.rows[indexes[k]];
        final pct = row.pct;
        double? fixed;
        if (pct == c.from) {
          fixed = c.to;
        } else if (k > 0 && bar != null && pct != null && pct > bar && pct < c.from) {
          fixed = ((bar + (pct - bar) * (c.to - bar) / (c.from - bar)) * 10).round() / 10;
        }
        if (fixed != null && fixed != pct) {
          plan.rows[indexes[k]] = row.withPct(fixed);
          changed++;
        }
      }
    }
  }
  return changed;
}
