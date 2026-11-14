import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_frontend/features/asignacion/domain/calendar_repository.dart';

DayState _s(int day, {int cycle = 1, int week = 2, bool done = true}) =>
    DayState(cycle: cycle, week: week, day: day, done: done);

int _first(List<DayState> states, {int dayCount = 3}) =>
    firstPendingDay(states, cycle: 1, week: 2, dayCount: dayCount);

void main() {
  test('without sessions it is day 1', () => expect(_first([]), 1));

  test('it is the first day without sets', () {
    expect(_first([_s(1)]), 2);
    expect(_first([_s(2)]), 1);
    expect(_first([_s(1), _s(3)]), 2);
  });

  test('pending states do not count as done', () {
    expect(_first([_s(1, done: false)]), 1);
  });

  test('with every day done it is day 1', () {
    expect(_first([_s(1), _s(2), _s(3)]), 1);
  });

  test('other weeks and cycles do not count', () {
    expect(_first([_s(1, week: 3), _s(1, cycle: 2)]), 1);
  });
}
