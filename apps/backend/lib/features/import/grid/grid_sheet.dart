import 'package:maktub_backend/features/import/sheets.dart';

/// The kind of a block of the planning grid.
enum GridBlockKind { warmUp, block, wod }

/// One exercise of a block in one week, as the grid writes it.
class GridEntry {
  const GridEntry({required this.row, required this.exercise, required this.sets, required this.load});

  /// The spreadsheet row (1-based CSV record) it comes from.
  final int row;
  final String exercise;

  /// Sets and reps as written: `4X6`, `10/10/8/6/4/2`, `7/2x5/3x3`, `3x10 c/lado`. May be empty.
  final String sets;

  /// The load column: a % (`0.65`), kilos (`mancuerna 12kg`) or a note (`barra de 15/20`, `con barra`). May be empty.
  final String load;
}

/// One block of one day in one week: the warm-up (`ENTRADA EN CALOR`), `BLOQUE n` or `WOD`.
class GridBlock {
  GridBlock(this.kind, this.row, {this.number});

  final GridBlockKind kind;

  /// The `n` of `BLOQUE n`.
  final int? number;
  final int row;
  final entries = <GridEntry>[];

  /// Free lines of the block (mobility, rest, a coach's remark, the WOD's text), in order.
  final notes = <String>[];

  // The warm-up writes its exercises as lines of one cell, and their sets one row each.
  final _warmUpNames = <String>[];
  final _warmUpSets = <(int, String)>[];
  int? _warmUpRow;

  String get name => switch (kind) {
    GridBlockKind.warmUp => 'Entrada en calor',
    GridBlockKind.block => 'Bloque $number',
    GridBlockKind.wod => 'WOD',
  };

  /// Pairs the warm-up's exercise lines with its sets rows, in order; the last sets row serves the rest.
  void _finish() {
    if (_warmUpNames.isEmpty) return;
    for (var i = 0; i < _warmUpNames.length; i++) {
      final sets = _warmUpSets.isEmpty ? (_warmUpRow!, '') : _warmUpSets[i < _warmUpSets.length ? i : _warmUpSets.length - 1];
      entries.add(GridEntry(row: sets.$1, exercise: _warmUpNames[i], sets: sets.$2, load: ''));
    }
    _warmUpNames.clear();
    _warmUpSets.clear();
  }
}

/// One RM of the grid's `KG RM` table (top right).
class GridRm {
  const GridRm({required this.exercise, required this.athlete, required this.kg, required this.row});

  final String exercise;

  /// The athlete's column header (`ANDI`, `ARI`).
  final String athlete;
  final double kg;
  final int row;
}

/// A planning grid of the old spreadsheet (`docs/planillas/csv/planificacion/*.csv`), as `reference/importar.py`
/// describes it: the four weeks in columns, five per week (sets and reps, load or note, exercise, weights used, empty),
/// and the days in rows, each one with its warm-up, numbered blocks and WOD.
class PlanningGrid {
  PlanningGrid._();

  /// Parses [csv]. Throws [FormatException] if the first row has no `SEMANA 1`.
  factory PlanningGrid.parse(String csv) {
    final grid = PlanningGrid._();
    final records = parseCsv(csv);
    if (records.isEmpty) throw const FormatException('La grilla está vacía.');
    String cell(int r, int c) => c < records[r].length ? records[r][c].trim() : '';

    final header = records.first;
    final weekColumns = <int, int>{};
    int? rmColumn;
    for (var c = 0; c < header.length; c++) {
      final text = header[c].trim().toUpperCase();
      final week = RegExp(r'^SEMANA\s*(\d+)$').firstMatch(text);
      if (week != null) weekColumns[int.parse(week.group(1)!)] = c;
      if (text == 'KG RM') rmColumn = c;
    }
    final first = weekColumns[1];
    if (first == null || first == 0) throw const FormatException('La grilla no tiene "SEMANA 1" en la primera fila.');
    grid.weeks.addAll(weekColumns.keys.toList()..sort());

    // The KG RM table: one column per athlete after the header.
    if (rmColumn != null) {
      final athletes = <int, String>{};
      for (var c = rmColumn + 1; c < header.length && header[c].trim().isNotEmpty; c++) {
        athletes[c] = header[c].trim();
      }
      for (var r = 1; r < records.length; r++) {
        final exercise = cell(r, rmColumn);
        if (exercise.isEmpty) continue;
        for (final MapEntry(key: c, value: athlete) in athletes.entries) {
          final kg = double.tryParse(cell(r, c).replaceAll(',', '.'));
          if (kg != null) grid.rms.add(GridRm(exercise: exercise, athlete: athlete, kg: kg, row: r + 1));
        }
      }
    }

    final dayColumn = first - 1;
    int? day;
    final current = <int, GridBlock?>{};
    void close() {
      for (final b in current.values) {
        b?._finish();
      }
      current.clear();
    }

    for (var r = 1; r < records.length; r++) {
      final row = r + 1;
      final label = cell(r, dayColumn);
      final dayMatch = RegExp(r'^d[ií]a\s*(\d+)', caseSensitive: false).firstMatch(label);
      if (dayMatch != null) {
        close();
        day = int.parse(dayMatch.group(1)!);
        grid.days.putIfAbsent(day, () => {for (final w in grid.weeks) w: <GridBlock>[]});
      }
      if (RegExp('no hicimos', caseSensitive: false).hasMatch(label)) {
        grid.skippedRows.add(row);
        continue;
      }
      if (day == null) continue;
      for (final w in grid.weeks) {
        final c = weekColumns[w]!;
        final a = cell(r, c), b = cell(r, c + 1), e = cell(r, c + 2);
        if (a.isEmpty && b.isEmpty && e.isEmpty) continue;
        final head = a.toUpperCase();
        void open(GridBlock block) {
          current[w]?._finish();
          current[w] = block;
          grid.days[day]![w]!.add(block);
        }

        if (head.startsWith('ENTRADA EN CALOR')) {
          open(GridBlock(GridBlockKind.warmUp, row));
          continue;
        }
        final weekLabel = RegExp(r'^SEMANA\s*\d+\s*(?:\((.*)\))?').firstMatch(head);
        if (weekLabel != null) {
          final remark = RegExp(r'\((.*)\)').firstMatch(a)?.group(1)?.trim();
          if (remark != null && remark.isNotEmpty) grid.dayRemarks['$day|$w'] = remark;
          continue;
        }
        final blockMatch = RegExp(r'^BLOQUE\s*(\d+)').firstMatch(head);
        if (blockMatch != null) {
          open(GridBlock(GridBlockKind.block, row, number: int.parse(blockMatch.group(1)!)));
          continue;
        }
        if (head.startsWith('WOD')) {
          final wod = GridBlock(GridBlockKind.wod, row);
          open(wod);
          wod.notes.addAll(_lines(a.substring(3)));
          wod.notes.addAll(_lines(b));
          continue;
        }
        final block = current[w];
        if (block == null) {
          grid.ignored.add('fila $row, semana $w: "${[a, b, e].where((s) => s.isNotEmpty).join(' | ')}" fuera de un bloque');
          continue;
        }
        switch (block.kind) {
          case GridBlockKind.warmUp:
            if (b.isNotEmpty) {
              block._warmUpRow ??= row;
              block._warmUpNames.addAll(_lines(b));
            }
            if (a.isNotEmpty) block._warmUpSets.add((row, a));
          case GridBlockKind.block:
            if (e.isNotEmpty) {
              block.entries.add(GridEntry(row: row, exercise: e, sets: a, load: b));
            } else {
              for (final text in [a, b]) {
                if (text.isEmpty) continue;
                if (RegExp(r'[\p{L}\d]', unicode: true).hasMatch(text)) {
                  block.notes.add(text);
                } else {
                  grid.ignored.add('fila $row, semana $w: "$text" (sin letras ni números)');
                }
              }
            }
          case GridBlockKind.wod:
            block.notes.addAll([..._lines(a), ..._lines(b)]);
        }
      }
    }
    close();
    return grid;
  }

  /// The week numbers (1-based), in order.
  final weeks = <int>[];

  /// Day number → week → its blocks in order.
  final days = <int, Map<int, List<GridBlock>>>{};

  /// `day|week` → what the week's header of that day says in parentheses ("andi no hizo este dia").
  final dayRemarks = <String, String>{};
  final rms = <GridRm>[];

  /// Rows marked "no hicimos esto": skipped.
  final skippedRows = <int>[];

  /// Cells that are not part of any block, or have no content.
  final ignored = <String>[];
}

List<String> _lines(String text) => [
  for (final l in text.split('\n'))
    if (l.trim().isNotEmpty) l.trim(),
];
