import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/sesion/domain/athlete_adjustments.dart';

void main() {
  group('which blocks take a per-exercise adjustment', () {
    for (final id in ['primario', 'secundario', 'accesorio']) {
      test('$id does', () {
        expect(
          blockTakesAdjustment(PlanBlock(name: 'B', categoryId: id)),
          isTrue,
        );
      });
    }

    for (final id in ['calentamiento', 'estiramiento', 'cardio', 'wod']) {
      test('$id does not', () {
        expect(
          blockTakesAdjustment(PlanBlock(name: 'B', categoryId: id)),
          isFalse,
        );
      });
    }
  });

  test('starts neutral', () {
    expect(const AthleteAdjustments().effectiveFor('sq'), 100);
  });

  test('the session level applies to every exercise', () {
    expect(const AthleteAdjustments().stepSession(5).effectiveFor('sq'), 105);
  });

  test('the exercise level wins over the session level, and only for it', () {
    final a = const AthleteAdjustments().stepSession(10).stepExercise('sq', -5);

    expect(a.effectiveFor('sq'), 105);
    expect(a.effectiveFor('bp'), 110);
  });

  test('a step of 0 removes the exercise level and resets the session', () {
    final a = const AthleteAdjustments().stepSession(10).stepExercise('sq', 5);

    expect(a.stepExercise('sq', 0).effectiveFor('sq'), 110);
    expect(a.stepSession(0).session, 100);
  });

  test('is a value: equal contents compare equal', () {
    expect(
      const AthleteAdjustments().stepExercise('sq', 5),
      const AthleteAdjustments().stepExercise('sq', 5),
    );
    expect(
      const AthleteAdjustments().stepExercise('sq', 5),
      isNot(const AthleteAdjustments().stepExercise('sq', -5)),
    );
  });
}
