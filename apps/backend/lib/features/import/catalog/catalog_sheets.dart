import 'package:maktub_backend/features/import/sheets.dart';

/// Sheet names and columns of the catalog (`reference/Esquema.gs`, HOJAS, plus `medida` and `inactivo`).
abstract final class CatalogSheetNames {
  static const exercises = 'Ejercicios';
  static const timers = 'Temporizadores';
  static const wods = 'WoDs';

  static const exerciseColumns = ['id', 'nombre', 'categoria', 'referencia', 'notas', 'medida', 'inactivo'];
  static const timerColumns = ['id', 'nombre', 'tipo', 'trabajo_seg', 'descanso_seg', 'rondas'];
  static const wodColumns = ['id', 'nombre', 'formato', 'temporizador', 'descripcion'];
}

/// How an exercise is measured in the old app (`MEDIDAS`). Empty or unknown reads as [weight].
enum SheetMeasure {
  weight('peso'),
  reps('reps'),
  time('tiempo');

  const SheetMeasure(this.cell);
  final String cell;
}

/// A row of Ejercicios, after merging the rows that repeat its id.
class SheetExercise {
  const SheetExercise({
    required this.id,
    required this.name,
    required this.categories,
    this.reference,
    this.notes,
    this.measure = SheetMeasure.weight,
    this.inactive = false,
    required this.lines,
  });

  final String id;
  final String name;

  /// Lowercase category ids, in order of appearance (more than one only when the id repeats).
  final List<String> categories;

  /// One of the basic lifts (`sentadilla`, `peso_muerto`, `bench`) or null.
  final String? reference;
  final String? notes;
  final SheetMeasure measure;
  final bool inactive;

  /// CSV lines it came from.
  final List<int> lines;
}

class SheetTimer {
  const SheetTimer({required this.id, required this.body, required this.line});

  final String id;

  /// The timer as `Temporizador` JSON without id, club, status or audit.
  final Map<String, dynamic> body;
  final int line;
}

class SheetWod {
  const SheetWod({
    required this.id,
    required this.name,
    this.format,
    this.timerId,
    this.description,
    required this.line,
  });

  final String id;
  final String name;

  /// `amrap`, `emom`, `tabata`, `for_time`... The WoD library has no field for it: the timer carries it.
  final String? format;

  /// Sheet id of a Temporizadores row.
  final String? timerId;
  final String? description;
  final int line;
}

/// The three catalog sheets, read and checked row by row.
class CatalogSheets {
  CatalogSheets._();

  /// Reads the rows. Rows that cannot be read go to [problems]; repeated ids are merged (exercises) or
  /// the last one wins (timers and WoDs, as the old app's `porId_`), and that goes to [notes].
  factory CatalogSheets.read({required Sheet exercises, required Sheet timers, required Sheet wods}) {
    final s = CatalogSheets._();
    s._readExercises(exercises);
    s._readTimers(timers);
    s._readWods(wods);
    return s;
  }

  final exercises = <SheetExercise>[];
  final timers = <SheetTimer>[];
  final wods = <SheetWod>[];
  final problems = <String>[];
  final notes = <String>[];

  static const _truthy = {'true', 'si', 'sí', 'verdadero', '1', 'x'};

  void _readExercises(Sheet sheet) {
    final byId = <String, SheetExercise>{};
    for (final r in sheet.rows) {
      final id = r['id'];
      final name = r['nombre'].replaceAll(RegExp(r'\s+'), ' ');
      final category = r['categoria'].toLowerCase();
      if (id.isEmpty || name.isEmpty || category.isEmpty) {
        problems.add('${sheet.name} línea ${r.line}: falta id, nombre o categoría.');
        continue;
      }
      final rawMeasure = r['medida'].toLowerCase();
      final measure = SheetMeasure.values.where((m) => m.cell == rawMeasure).firstOrNull;
      if (rawMeasure.isNotEmpty && measure == null) {
        notes.add('${sheet.name} línea ${r.line} ($id): medida "$rawMeasure" desconocida, se lee como peso.');
      }
      final row = SheetExercise(
        id: id,
        name: name,
        categories: [category],
        reference: r.optional('referencia')?.toLowerCase(),
        notes: r.optional('notas'),
        measure: measure ?? SheetMeasure.weight,
        inactive: _truthy.contains(r['inactivo'].toLowerCase()),
        lines: [r.line],
      );
      final previous = byId[id];
      if (previous == null) {
        byId[id] = row;
        continue;
      }
      // The old app resolved an id to its last row; empty cells of the last row keep the earlier value,
      // because an empty `medida` is only the legacy default.
      byId[id] = SheetExercise(
        id: id,
        name: row.name,
        categories: [...previous.categories, ...row.categories.where((c) => !previous.categories.contains(c))],
        reference: row.reference ?? previous.reference,
        notes: row.notes ?? previous.notes,
        measure: rawMeasure.isEmpty ? previous.measure : row.measure,
        inactive: row.inactive,
        lines: [...previous.lines, ...row.lines],
      );
      notes.add(
        '${sheet.name}: el id "$id" se repite (líneas ${byId[id]!.lines.join(', ')}: '
        '"${previous.name}" y "${row.name}"); queda un solo ejercicio "${row.name}" con las categorías '
        '${byId[id]!.categories.join(' y ')}.',
      );
    }
    exercises.addAll(byId.values);
  }

  void _readTimers(Sheet sheet) {
    final byId = <String, SheetTimer>{};
    for (final r in sheet.rows) {
      final id = r['id'];
      if (id.isEmpty || r['nombre'].isEmpty || r['tipo'].isEmpty) {
        problems.add('${sheet.name} línea ${r.line}: falta id, nombre o tipo.');
        continue;
      }
      int? number(String column, int empty) {
        final v = r[column];
        return v.isEmpty ? empty : int.tryParse(v) ?? double.tryParse(v.replaceAll(',', '.'))?.round();
      }

      final work = number('trabajo_seg', 0);
      final rest = number('descanso_seg', 0);
      final rounds = number('rondas', 1);
      if (work == null || rest == null || rounds == null) {
        problems.add('${sheet.name} línea ${r.line} ($id): trabajo, descanso o rondas no es un número.');
        continue;
      }
      if (byId.containsKey(id)) {
        notes.add('${sheet.name}: el id "$id" se repite; vale la última fila (línea ${r.line}).');
      }
      byId[id] = SheetTimer(
        id: id,
        line: r.line,
        body: {
          'nombre': r['nombre'],
          'tipo': r['tipo'].toLowerCase(),
          'trabajoSeg': work,
          'descansoSeg': rest,
          'rondas': rounds,
        },
      );
    }
    timers.addAll(byId.values);
  }

  void _readWods(Sheet sheet) {
    final byId = <String, SheetWod>{};
    for (final r in sheet.rows) {
      final id = r['id'];
      if (id.isEmpty || r['nombre'].isEmpty) {
        problems.add('${sheet.name} línea ${r.line}: falta id o nombre.');
        continue;
      }
      if (byId.containsKey(id)) {
        notes.add('${sheet.name}: el id "$id" se repite; vale la última fila (línea ${r.line}).');
      }
      byId[id] = SheetWod(
        id: id,
        name: r['nombre'],
        format: r.optional('formato')?.toLowerCase(),
        timerId: r.optional('temporizador'),
        description: r.optional('descripcion'),
        line: r.line,
      );
    }
    wods.addAll(byId.values);
  }
}
