import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/catalogo/domain/exercise_draft.dart';

void main() {
  group('barChoice', () {
    test('a chosen bar or "no bar" is shown as it is', () {
      expect(
        barChoice(15, metrics: const [Metric.loadPctRm], clubBarKg: 20),
        15,
      );
      expect(
        barChoice(noBarKg, metrics: const [Metric.loadPctRm], clubBarKg: 20),
        noBarKg,
      );
    });

    test('with no bar set, an exercise by % of RM shows the club bar', () {
      expect(
        barChoice(null, metrics: const [Metric.loadPctRm], clubBarKg: 20),
        20,
      );
    });

    test('with no bar set, a fixed-load exercise shows no bar', () {
      expect(
        barChoice(null, metrics: const [Metric.fixedLoad], clubBarKg: 20),
        noBarKg,
      );
    });
  });
}
