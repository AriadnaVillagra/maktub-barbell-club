import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/plan/domain/prescription_defaults.dart';
import 'package:maktub_frontend/features/plan/presentation/plan_labels.dart';

import '../catalogo/catalog_fakes.dart';

void main() {
  const timers = ['desc_90', 'desc_120', 'desc_180', 'emom_10'];
  final pct = ex('squat', 'Sentadilla');
  final fixed = ex(
    'curl',
    'Curl',
    metrics: const [Metric.fixedLoad, Metric.reps],
  );

  List<(int?, double?)> sets(Prescription p) => [
    for (final s in p.sets) (s.reps, s.pct),
  ];

  Prescription make(Exercise e, String? category, [Iterable<String>? t]) =>
      defaultPrescription(e, categoryId: category, activeTimerIds: t ?? timers);

  test('primario: the reference sets with % and desc_180', () {
    final p = make(pct, 'primario');
    expect(p.exerciseId, 'squat');
    expect(sets(p), [(8, 65.0), (5, 72.5), (3, 80.0), (3, 80.0)]);
    expect(p.timerId, 'desc_180');
  });

  test('secundario: the reference sets with % and desc_120', () {
    final p = make(pct, 'secundario');
    expect(sets(p), [(6, 50.0), (6, 50.0), (6, 50.0), (6, 50.0)]);
    expect(p.timerId, 'desc_120');
  });

  test('accesorio: reps without % and desc_90', () {
    final p = make(pct, 'accesorio');
    expect(sets(p), [(10, null), (10, null), (10, null)]);
    expect(p.timerId, 'desc_90');
  });

  test('a fixed-load exercise gets reps and no %, in any default category', () {
    expect(sets(make(fixed, 'primario')), [
      (8, null),
      (5, null),
      (3, null),
      (3, null),
    ]);
    expect(make(fixed, 'primario').sets.every((s) => s.kg == null), isTrue);
  });

  test('any other category gets no sets and no timer', () {
    for (final c in ['calentamiento', 'wod', 'cardio', 'other', null]) {
      final p = make(pct, c);
      expect(p.exerciseId, 'squat');
      expect(p.sets, isEmpty);
      expect(p.timerId, isNull);
    }
  });

  test('without the default timer in the club the timer stays empty', () {
    final p = make(pct, 'primario', ['desc_90']);
    expect(p.timerId, isNull);
    expect(p.sets, hasLength(4));
  });

  test('an exercise that does not measure reps gets no sets', () {
    final p = make(
      ex('run', 'Correr', metrics: const [Metric.time]),
      'primario',
    );
    expect(p.sets, isEmpty);
  });

  test('setsSummary reads reps and %', () {
    expect(
      setsSummary(make(pct, 'primario').sets),
      '8 × 65 %, 5 × 72,5 %, 3 × 80 %, 3 × 80 %',
    );
    expect(setsSummary(make(pct, 'accesorio').sets), '10, 10, 10');
  });
}
