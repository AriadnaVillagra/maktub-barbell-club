import 'dart:io';

import 'package:maktub_backend/features/import/sheets.dart';
import 'package:test/test.dart';

void main() {
  group('parseCsv', () {
    test('reads quoted fields with commas, doubled quotes and line breaks', () {
      expect(parseCsv('a,b\n"x, y","say ""hi""\nthere"\n'), [
        ['a', 'b'],
        ['x, y', 'say "hi"\nthere'],
      ]);
    });

    test('accepts CRLF, a BOM and a last line without break', () {
      expect(parseCsv('﻿a,b\r\n1,\r\n2,3'), [
        ['a', 'b'],
        ['1', ''],
        ['2', '3'],
      ]);
    });
  });

  group('Sheet', () {
    test('finds columns by header, ignores extra ones and skips blank rows', () {
      final sheet = Sheet.parse('Hoja', 'extra,id,nombre\nz,1, Uno \n,,\nz,2,Dos\n', columns: ['id', 'nombre']);
      expect(sheet.rows.map((r) => r['nombre']), ['Uno', 'Dos']);
      expect(sheet.rows.map((r) => r.line), [2, 4]);
      expect(sheet.rows.first.optional('falta'), isNull);
    });

    test('a missing column stops the import', () {
      expect(
        () => Sheet.parse('Hoja', 'id\n1\n', columns: ['id', 'nombre']),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('nombre'))),
      );
    });

    test('a missing sheet file stops the import', () {
      final dir = Directory.systemTemp.createTempSync('sheets_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      expect(() => SheetDirectory(dir.path).read('Ejercicios', columns: ['id']), throwsA(isA<FileSystemException>()));
    });
  });
}
