import 'dart:io';

/// One row of a sheet, read by column name. [line] is the 1-based line in the CSV (the header is line 1).
class SheetRow {
  const SheetRow(this.line, this._cells);

  final int line;
  final Map<String, String> _cells;

  /// The trimmed cell of [column]; empty when the column or the cell is missing.
  String operator [](String column) => (_cells[column] ?? '').trim();

  /// The cell of [column], or null when it is empty.
  String? optional(String column) {
    final v = this[column];
    return v.isEmpty ? null : v;
  }
}

/// A sheet of the old spreadsheet, exported as CSV (E8.1). Columns are found by header name, so extra
/// columns are ignored and their order does not matter (the CSVs rule over `reference/Esquema.gs`, D18).
class Sheet {
  Sheet._(this.name, this.headers, this.rows);

  /// Parses [csv]. Throws [FormatException] if one of [columns] is missing from the header. Rows where
  /// every cell is empty are skipped, like the old app did.
  factory Sheet.parse(String name, String csv, {required List<String> columns}) {
    final records = parseCsv(csv);
    if (records.isEmpty) throw FormatException('La hoja $name está vacía (sin encabezado).');
    final headers = [for (final h in records.first) h.trim()];
    final missing = [
      for (final c in columns)
        if (!headers.contains(c)) c,
    ];
    if (missing.isNotEmpty) {
      throw FormatException('A la hoja $name le faltan las columnas: ${missing.join(', ')}.');
    }
    final rows = <SheetRow>[];
    for (var i = 1; i < records.length; i++) {
      final record = records[i];
      if (record.every((c) => c.trim().isEmpty)) continue;
      rows.add(SheetRow(i + 1, {for (var c = 0; c < headers.length && c < record.length; c++) headers[c]: record[c]}));
    }
    return Sheet._(name, headers, rows);
  }

  final String name;
  final List<String> headers;
  final List<SheetRow> rows;
}

/// The folder with the exported CSVs, one file per sheet (`<Nombre>.csv`, as E8.1 left them).
class SheetDirectory {
  SheetDirectory(this.path);

  final String path;

  /// Reads the sheet [name]. Throws [FileSystemException] if the file is missing: an incomplete export
  /// must stop the import (E8, "Contingencia").
  Sheet read(String name, {required List<String> columns}) {
    final file = File('$path${Platform.pathSeparator}$name.csv');
    if (!file.existsSync()) throw FileSystemException('Falta la hoja exportada', file.path);
    return Sheet.parse(name, file.readAsStringSync(), columns: columns);
  }
}

/// RFC 4180 CSV: quoted fields may hold commas, line breaks and doubled quotes. Accepts `\n` and `\r\n`
/// and a leading BOM.
List<List<String>> parseCsv(String text) {
  final records = <List<String>>[];
  var record = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var i = text.startsWith('﻿') ? 1 : 0;

  void endField() {
    record.add(field.toString());
    field.clear();
  }

  void endRecord() {
    endField();
    records.add(record);
    record = <String>[];
  }

  while (i < text.length) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == ',') {
      endField();
    } else if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') {
      endRecord();
      i++;
    } else if (ch == '\n') {
      endRecord();
    } else {
      field.write(ch);
    }
    i++;
  }
  if (field.isNotEmpty || record.isNotEmpty) endRecord();
  return records;
}
