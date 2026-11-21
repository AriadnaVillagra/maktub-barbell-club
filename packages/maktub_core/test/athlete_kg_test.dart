import 'package:maktub_core/maktub_core.dart';
import 'package:test/test.dart';

final _audit = Auditoria.nueva('coach', ahora: DateTime.utc(2026, 11, 8));

Exercise _ex(String id, List<Metric> metrics) =>
    Exercise(id: id, clubId: 'c1', name: id, metrics: metrics, categoryIds: const ['accesorio'], auditoria: _audit);

final _catalog = {
  'press': _ex('press', const [Metric.fixedLoad, Metric.reps]),
  'squat': _ex('squat', const [Metric.loadPctRm, Metric.reps]),
  'plank': _ex('plank', const [Metric.time]),
};

Plan _plan(List<PlanSet> sets, {String exerciseId = 'press', PlanType type = PlanType.regular}) => Plan(
  id: 'p1',
  clubId: 'c1',
  name: 'Noviembre',
  type: type,
  weekModels: [
    WeekModel(
      id: 'A',
      name: 'A',
      days: [
        PlanDay(
          blocks: [
            PlanBlock(
              name: 'Accesorios',
              categoryId: 'accesorio',
              prescriptions: [Prescription(exerciseId: exerciseId, sets: sets)],
            ),
          ],
        ),
      ],
    ),
  ],
  weekAssignment: const ['A', 'A', 'A', 'A'],
  auditoria: _audit,
);

List<PlanProblem> _validate(Plan plan, List<String> athleteIds) =>
    validatePlan(plan, exerciseById: (id) => _catalog[id], athleteIds: athleteIds);

PlanProblem _missing(int set, String athleteId) => PlanProblem(
  PlanProblemCode.setWithoutAthleteKg,
  weekModelIndex: 0,
  dayIndex: 0,
  blockIndex: 0,
  prescriptionIndex: 0,
  setIndex: set,
  athleteId: athleteId,
);

Assignment _assignment(
  String id, {
  required List<AssignmentMember> members,
  AssignmentStatus status = AssignmentStatus.active,
  DateTime? start,
}) => Assignment(
  id: id,
  clubId: 'c1',
  planId: 'p1',
  members: members,
  startDate: start ?? DateTime.utc(2026, 11, 2),
  status: status,
  auditoria: _audit,
);

AssignmentMember _in(String athleteId, {DateTime? to}) =>
    AssignmentMember(athleteId: athleteId, from: DateTime.utc(2026, 11, 2), to: to);

void main() {
  group('isKgExercise', () {
    test('only an exercise in kilos that is not by % of RM', () {
      expect(isKgExercise(_catalog['press']!), isTrue);
      expect(isKgExercise(_catalog['squat']!), isFalse);
      expect(isKgExercise(_catalog['plank']!), isFalse);
      expect(isKgExercise(_ex('both', const [Metric.loadPctRm, Metric.fixedLoad])), isFalse);
    });
  });

  group('asksKgPerAthlete', () {
    test('only for more than one athlete', () {
      expect(asksKgPerAthlete(const []), isFalse);
      expect(asksKgPerAthlete(const ['ari']), isFalse);
      expect(asksKgPerAthlete(const ['ari', 'ari']), isFalse);
      expect(asksKgPerAthlete(const ['ari', 'andi']), isTrue);
    });
  });

  group('validatePlan with kilos per athlete', () {
    test('a set in kilos needs every athlete\'s kilos, one problem per athlete missing', () {
      final plan = _plan(const [
        PlanSet(reps: 10, byAthlete: {'ari': AthleteSetLoad(kg: 12), 'andi': AthleteSetLoad(kg: 16)}),
        PlanSet(reps: 10, byAthlete: {'ari': AthleteSetLoad(kg: 12)}),
        PlanSet(reps: 10),
      ]);
      expect(_validate(plan, const ['ari', 'andi']), [_missing(1, 'andi'), _missing(2, 'ari'), _missing(2, 'andi')]);
    });

    test('a set planned with one weight counts for every athlete (old plans keep publishing)', () {
      expect(_validate(_plan(const [PlanSet(reps: 10, kg: 14)]), const ['ari', 'andi']), isEmpty);
    });

    test('zero kilos is missing', () {
      final plan = _plan(const [
        PlanSet(reps: 10, byAthlete: {'ari': AthleteSetLoad(kg: 0), 'andi': AthleteSetLoad(kg: 16)}),
      ]);
      expect(_validate(plan, const ['ari', 'andi']), [_missing(0, 'ari')]);
    });

    test('one athlete, or none known, asks for no kilos (as before)', () {
      final plan = _plan(const [PlanSet(reps: 10)]);
      expect(_validate(plan, const ['ari']), isEmpty);
      expect(_validate(plan, const []), isEmpty);
    });

    test('an exercise by % of RM is not asked for kilos per athlete', () {
      final plan = _plan(const [PlanSet(reps: 5, pct: 70)], exerciseId: 'squat');
      expect(_validate(plan, const ['ari', 'andi']), isEmpty);
    });

    test('a history plan keeps its relaxed rules', () {
      final plan = _plan(const [PlanSet(reps: 10)], type: PlanType.history);
      expect(_validate(plan, const ['ari', 'andi']), isEmpty);
      expect(historyPlanAccepts, contains(PlanProblemCode.setWithoutAthleteKg));
    });
  });

  group('planAthleteIds', () {
    test('the current athletes of the active assignments, once each', () {
      final ids = planAthleteIds([
        _assignment(
          'a1',
          members: [
            _in('ari'),
            _in('andi'),
            _in('gone', to: DateTime.utc(2026, 11, 10)),
          ],
        ),
        _assignment('a2', members: [_in('andi'), _in('lu')]),
        _assignment('a3', members: [_in('old')], status: AssignmentStatus.ended),
      ]);
      expect(ids, ['ari', 'andi', 'lu']);
    });

    test('without an active one, everyone in the latest, if it ended', () {
      final ids = planAthleteIds([
        _assignment('old', members: [_in('x')], status: AssignmentStatus.ended, start: DateTime.utc(2026, 9, 1)),
        _assignment(
          'new',
          members: [
            _in('ari'),
            _in('andi', to: DateTime.utc(2026, 11, 10)),
          ],
          status: AssignmentStatus.ended,
        ),
      ]);
      expect(ids, ['ari', 'andi']);
    });

    test('a paused one gives its current athletes', () {
      final ids = planAthleteIds([
        _assignment(
          'p',
          members: [
            _in('ari'),
            _in('andi', to: DateTime.utc(2026, 11, 10)),
          ],
          status: AssignmentStatus.paused,
        ),
      ]);
      expect(ids, ['ari']);
    });

    test('a plan never assigned is for nobody yet', () {
      expect(planAthleteIds(const []), isEmpty);
    });
  });
}
