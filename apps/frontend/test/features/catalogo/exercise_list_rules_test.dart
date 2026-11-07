import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/catalogo/domain/exercise_list_rules.dart';

import 'catalog_fakes.dart';

void main() {
  final all = [
    ex('a', 'Sentadilla', clubId: clubPlataforma),
    ex('b', 'Curl', categories: ['accessory']),
    ex('c', 'Antiguo', status: CatalogStatus.archived),
    ex('d', 'Ajeno', clubId: 'c2'),
  ];

  test('lists visible active exercises by name, with archived on request', () {
    expect(
      [for (final e in listedExercises(all, clubId: 'c1')) e.name],
      ['Curl', 'Sentadilla'],
    );
    expect(
      [
        for (final e in listedExercises(all, clubId: 'c1', showArchived: true))
          e.name,
      ],
      ['Antiguo', 'Curl', 'Sentadilla'],
    );
  });

  test('filters by category and by accent-insensitive query', () {
    expect(
      [
        for (final e in listedExercises(
          all,
          clubId: 'c1',
          categoryId: 'accessory',
        ))
          e.name,
      ],
      ['Curl'],
    );
    expect(
      [
        for (final e in listedExercises(all, clubId: 'c1', query: 'SENTA'))
          e.name,
      ],
      ['Sentadilla'],
    );
  });
}
