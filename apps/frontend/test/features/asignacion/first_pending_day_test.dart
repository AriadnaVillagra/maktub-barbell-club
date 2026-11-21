import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_frontend/features/asignacion/domain/calendar_repository.dart';

DayState _s(
  int day, {
  int cycle = 1,
  int week = 2,
  DayProgressStatus status = DayProgressStatus.done,
}) => DayState(cycle: cycle, week: week, day: day, status: status);

int _first(List<DayState> states, {int dayCount = 3}) =>
    firstPendingDay(states, cycle: 1, week: 2, dayCount: dayCount);

void main() {
  test('without sessions it is day 1', () => expect(_first([]), 1));

  test('it is the first day not done', () {
    expect(_first([_s(1)]), 2);
    expect(_first([_s(2)]), 1);
    expect(_first([_s(1), _s(3)]), 2);
  });

  test('pending states do not count as done', () {
    expect(_first([_s(1, status: DayProgressStatus.pending)]), 1);
  });

  test('a day in progress is not done: it is the one that opens', () {
    expect(_first([_s(1), _s(2, status: DayProgressStatus.inProgress)]), 2);
  });

  test('with every day done it is day 1', () {
    expect(_first([_s(1), _s(2), _s(3)]), 1);
  });

  test('other weeks and cycles do not count', () {
    expect(_first([_s(1, week: 3), _s(1, cycle: 2)]), 1);
  });
}
