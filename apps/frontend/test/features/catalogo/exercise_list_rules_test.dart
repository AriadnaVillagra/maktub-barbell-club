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
      ['Antiguo'],
    );
  });

  test('reference candidates share the metric, so a press never offers a bike', () {
    final audit = Auditoria(creadoPor: 'u', creadoEn: DateTime.utc(2026));
    Exercise make(String id, Metric metric) => Exercise(
      id: id,
      clubId: 'c1',
      name: id,
      metrics: [metric],
      defaultMetric: metric,
      auditoria: audit,
    );
    final items = [make('banca', Metric.loadPctRm), make('bici', Metric.calories)];
    expect(
      referenceCandidates(items, clubId: 'c1', defaultMetric: Metric.loadPctRm).map((e) => e.id),
      ['banca'],
    );
    expect(
      referenceCandidates(items, clubId: 'c1', metrics: {Metric.calories}).map((e) => e.id),
      ['bici'],
    );
    expect(referenceCandidates(items, clubId: 'c1'), hasLength(2));
    expect(
      referenceCandidates(items, clubId: 'c1', exerciseId: 'banca', defaultMetric: Metric.loadPctRm),
      isEmpty,
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
