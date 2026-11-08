import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_frontend/features/atletas/domain/athlete_repository.dart';
import 'package:maktub_frontend/features/atletas/domain/sheet_rows.dart';

import 'fakes.dart';

void main() {
  test('history is newest first and the RM in force today is the latest not in the future', () {
    final sheet = AthleteSheet(
      athleteId: 'a1',
      references: [
        rm('old', 'sq', 100, DateTime.utc(2026, 1, 1)),
        rm('future', 'sq', 130, DateTime.utc(2026, 12, 1)),
        rm('now', 'sq', 120, DateTime.utc(2026, 10, 1)),
      ],
    );
    final row = sheetRows(sheet, today: today).single;
    expect(row.rms.map((r) => r.id), ['future', 'now', 'old']);
    expect(row.currentRm!.id, 'now');
  });

  test(
    'a newer RM resets the factor to 100 and an older one leaves it standing',
    () {
      final sheet = AthleteSheet(
        athleteId: 'a1',
        references: [
          rm('a', 'sq', 100, DateTime.utc(2026, 1, 1)),
          rm('b', 'dl', 100, DateTime.utc(2026, 1, 1)),
          rm('c', 'dl', 110, DateTime.utc(2026, 10, 1)),
        ],
        factors: [
          factor('f1', 'sq', 80, DateTime.utc(2026, 5, 1)),
          factor('f2', 'dl', 80, DateTime.utc(2026, 5, 1)),
        ],
      );
      final rows = {
        for (final r in sheetRows(sheet, today: today)) r.exerciseId: r,
      };
      expect(rows['sq']!.factor, 80);
      expect(rows['dl']!.factor, 100);
    },
  );

  test('exercises with only a fixed weight appear, and other reference types are left out', () {
    final sheet = AthleteSheet(
      athleteId: 'a1',
      fixedWeights: [fixed('curl', 12.5)],
    );
    final row = sheetRows(sheet, today: today).single;
    expect(row.exerciseId, 'curl');
    expect(row.rms, isEmpty);
    expect(row.currentRm, isNull);
    expect(row.factor, 100);
    expect(row.fixedWeight!.kg, 12.5);
    expect(
      sheetRows(const AthleteSheet(athleteId: 'a1'), today: today),
      isEmpty,
    );
  });
}
