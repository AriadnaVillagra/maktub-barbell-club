import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_frontend/features/sesion/domain/opening_day.dart';

void main() {
  test('with no recorded sets it is day 1', () {
    expect(firstPendingDay(3, const {}), 1);
  });

  test('it is the first day without recorded sets', () {
    expect(firstPendingDay(4, const {1, 2, 4}), 3);
    expect(firstPendingDay(4, const {2}), 1);
  });

  test('when every day has recorded sets it is day 1', () {
    expect(firstPendingDay(3, const {1, 2, 3}), 1);
  });

  test('a week with no days is day 1', () {
    expect(firstPendingDay(0, const {}), 1);
  });
}
