import 'package:maktub_core/maktub_core.dart';

final audit = Auditoria.nueva('coach-1', ahora: DateTime.utc(2026, 11, 1));

Session session(
  String id, {
  String clubId = 'club-a',
  String planId = 'p1',
  required DateTime date,
  List<String> present = const ['ath-1'],
  int week = 1,
  int day = 1,
  String? note,
  DateTime? createdAt,
}) => Session(
  id: id,
  clubId: clubId,
  assignmentId: 'as-$planId',
  planId: planId,
  cycle: 1,
  week: week,
  day: day,
  date: date,
  presentAthleteIds: present,
  note: note,
  auditoria: Auditoria.nueva('coach-1', ahora: createdAt ?? date),
);

SetRecord record(
  String sessionId, {
  String clubId = 'club-a',
  String athleteId = 'ath-1',
  String exerciseId = 'squat',
  String exerciseName = 'Sentadilla',
  int block = 0,
  int prescription = 0,
  int set = 0,
  bool done = true,
  bool estimated = false,
  double? kg,
  int? reps,
  double? workFactor,
  double? pctReal,
  PlanSet target = const PlanSet(),
  String? note,
}) => SetRecord(
  id: '$sessionId-$athleteId-$block-$prescription-$set',
  clubId: clubId,
  sessionId: sessionId,
  athleteId: athleteId,
  exerciseId: exerciseId,
  exerciseName: exerciseName,
  blockIndex: block,
  prescriptionIndex: prescription,
  setIndex: set,
  target: target,
  done: done,
  estimated: estimated,
  kg: kg,
  reps: reps,
  workFactor: workFactor,
  pctReal: pctReal,
  note: note,
  writtenBy: 'user-1',
  auditoria: audit,
);

/// A published plan whose week 1 has one day: block "Principal" with squat 3 sets and bench 2 sets, then a
/// block "Movilidad" with no exercises.
Plan plan({
  String id = 'p1',
  String clubId = 'club-a',
  String name = 'Abril 2026',
  PlanType type = PlanType.history,
  Map<String, AthleteSetLoad> byAthlete = const {},
}) {
  final day = PlanDay(
    name: 'Pierna',
    blocks: [
      PlanBlock(
        name: 'Principal',
        prescriptions: [
          Prescription(
            exerciseId: 'squat',
            sets: [
              PlanSet(reps: 5, pct: 70, byAthlete: byAthlete),
              const PlanSet(reps: 5, pct: 75),
              const PlanSet(reps: 5, pct: 80),
            ],
          ),
          const Prescription(
            exerciseId: 'bench',
            sets: [PlanSet(reps: 8), PlanSet(reps: 8)],
          ),
        ],
      ),
      const PlanBlock(name: 'Movilidad', prescriptions: [Prescription(sets: [])]),
    ],
  );
  final model = WeekModel(id: 'm1', name: 'A', days: [day]);
  return Plan(
    id: id,
    clubId: clubId,
    name: name,
    type: type,
    weekModels: [model],
    weekAssignment: const ['m1', 'm1', 'm1', 'm1'],
    published: PublishedPlan(
      weekModels: [model],
      weekAssignment: const ['m1', 'm1', 'm1', 'm1'],
      publishedAt: DateTime.utc(2026, 4, 1),
      publishedBy: 'coach-1',
    ),
    auditoria: audit,
  );
}
