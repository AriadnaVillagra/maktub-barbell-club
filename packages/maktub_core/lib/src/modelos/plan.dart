/// Plan (F5; docs/diseno.md, "Plan y asignación", "Métricas de un ejercicio" and "Cómo se recorre un bloque").
///
/// A plan has up to a handful of week models (A, B, C...) and a 4-position assignment that says which
/// week model each week of the cycle uses. A week model is 1 to 7 days; a day is an ordered list of
/// blocks; a block is an ordered list of prescriptions; a prescription is an exercise plus its sets,
/// one by one. Assigning a plan to a group of athletes is a different document (E6).
///
/// Identifiers are English; the wire (JSON keys and enum values) stays Spanish like the other contracts.
/// Models never throw on a structurally invalid plan (empty days, missing exercise...): a draft must be
/// representable, and `validatePlan` returns every problem. `fromJson` only throws on malformed JSON
/// (wrong types, unknown enum values).
library;

import 'base.dart';
import 'cable.dart';
import 'json.dart';

/// Number of weeks in a cycle: the assignment always has this many positions.
const planCycleWeeks = 4;

/// A week model has between [minDaysPerWeek] and [maxDaysPerWeek] days.
const minDaysPerWeek = 1;
const maxDaysPerWeek = 7;

/// Regular plans repeat forever; test plans last one cycle and produce new references (diseno, "Planes de test").
enum PlanType implements ConCable {
  regular('regular'),
  test('test');

  const PlanType(this.cable);
  @override
  final String cable;

  static PlanType deCable(Object? v) => desdeCable(values, v, 'Tipo de plan');
}

/// How a block is walked (diseno, "Cómo se recorre un bloque"). M1 only runs [sequential].
enum ExecutionMode implements ConCable {
  /// All the sets of exercise 1, then all of exercise 2...
  sequential('secuencial'),

  /// Set 1 of each exercise, then set 2 of each...
  circuit('circuito'),

  /// Driven by a timer: AMRAP, EMOM, tabata, for time, intervals.
  timed('por_tiempo');

  const ExecutionMode(this.cable);
  @override
  final String cable;

  static ExecutionMode deCable(Object? v) =>
      desdeCable(values, v, 'Modo de ejecución');
}

/// How the athletes share a block. It is the plan's default; it can change live during the session.
enum AthleteMode implements ConCable {
  /// Everybody does the same step at once.
  simultaneous('simultaneo'),

  /// One athlete after the other; one's rest is the other's turn.
  turns('por_turnos');

  const AthleteMode(this.cable);
  @override
  final String cable;

  static AthleteMode deCable(Object? v) =>
      desdeCable(values, v, 'Modo de atletas');
}

Auditoria _auditoria(Object? v) =>
    Auditoria.fromJson((v as Map).cast<String, dynamic>());

/// One set with its targets. Each field is a target in one of the exercise's metrics (diseno, "Métricas de un
/// ejercicio"); a set normally fills only the ones its exercise measures. Nothing here is a result: what the
/// athlete did is recorded in the session.
class PlanSet {
  const PlanSet({
    this.reps,
    this.maxReps = false,
    this.pct,
    this.kg,
    this.seconds,
    this.distanceM,
    this.pctOfMark,
    this.paceSecPerKm,
    this.pacePct,
    this.zone,
    this.calories,
    this.attempt,
  });

  /// Target repetitions.
  final int? reps;

  /// "Max." instead of a number of reps.
  final bool maxReps;

  /// Percent of the RM the load is prescribed on (80 = 80 %). Before the athlete's work factor.
  final double? pct;

  /// Fixed kilos per athlete, or the ballast of a bodyweight exercise.
  final double? kg;

  /// Target duration, in seconds.
  final int? seconds;

  /// Target distance, in meters.
  final double? distanceM;

  /// Percent of the athlete's time or distance mark (100 = the mark itself).
  final double? pctOfMark;

  /// Absolute pace, in seconds per kilometer.
  final double? paceSecPerKm;

  /// Pace relative to the athlete's reference pace (100 = the same).
  final double? pacePct;

  /// Heart rate zone.
  final int? zone;
  final double? calories;

  /// 1, 2 or 3 for the opening, second and third attempt of a tournament-style test. Its weight is chosen
  /// live, so [kg] stays null. Null for every other set.
  final int? attempt;

  factory PlanSet.fromJson(Json j) => PlanSet(
    reps: enteroOpcional(j['reps']),
    maxReps: j['repsMax'] == true,
    pct: numOpcional(j['pct']),
    kg: numOpcional(j['kilos']),
    seconds: enteroOpcional(j['segundos']),
    distanceM: numOpcional(j['distanciaM']),
    pctOfMark: numOpcional(j['pctMarca']),
    paceSecPerKm: numOpcional(j['ritmoSegKm']),
    pacePct: numOpcional(j['ritmoPct']),
    zone: enteroOpcional(j['zona']),
    calories: numOpcional(j['calorias']),
    attempt: enteroOpcional(j['intento']),
  );

  Json toJson() => sinNulos({
    'reps': reps,
    'repsMax': maxReps ? true : null,
    'pct': pct,
    'kilos': kg,
    'segundos': seconds,
    'distanciaM': distanceM,
    'pctMarca': pctOfMark,
    'ritmoSegKm': paceSecPerKm,
    'ritmoPct': pacePct,
    'zona': zone,
    'calorias': calories,
    'intento': attempt,
  });
}

/// An exercise with its sets, one by one (a ramp is just sets that differ).
class Prescription {
  const Prescription({
    this.exerciseId,
    this.sets = const [],
    this.note,
    this.timerId,
    this.barKg,
  });

  /// Null while the coach has not chosen one (a draft); a saved plan always has it.
  final String? exerciseId;
  final List<PlanSet> sets;

  /// Free text (note / RPE); never interpreted.
  final String? note;

  /// Own timer; replaces the block's default rest timer.
  final String? timerId;

  /// Bar for this prescription, in kg. Replaces the exercise's `barKg` when present; null means use the
  /// exercise's. Positive when present.
  final double? barKg;

  factory Prescription.fromJson(Json j) => Prescription(
    exerciseId: textoOpcional(j['ejercicioId']),
    sets: [for (final s in listaJson(j['series'])) PlanSet.fromJson(s)],
    note: textoOpcional(j['nota']),
    timerId: textoOpcional(j['temporizadorId']),
    barKg: numOpcional(j['barraKg']),
  );

  Json toJson() => sinNulos({
    'ejercicioId': exerciseId,
    'series': [for (final s in sets) s.toJson()],
    'nota': note,
    'temporizadorId': timerId,
    'barraKg': barKg,
  });
}

/// A named group of prescriptions with a category that filters which exercises it admits.
class PlanBlock {
  const PlanBlock({
    required this.name,
    this.categoryId,
    this.executionMode = ExecutionMode.sequential,
    this.athleteMode = AthleteMode.simultaneous,
    this.timerId,
    this.prescriptions = const [],
  });

  final String name;

  /// Id of a catalog `Category`. Null while it is a draft; a saved plan always has it.
  final String? categoryId;
  final ExecutionMode executionMode;

  /// The plan's default; changed live in the session.
  final AthleteMode athleteMode;

  /// Default rest timer of the block, or the block's own timer when [executionMode] is `timed`.
  final String? timerId;
  final List<Prescription> prescriptions;

  factory PlanBlock.fromJson(Json j) => PlanBlock(
    name: '${j['nombre'] ?? ''}',
    categoryId: textoOpcional(j['categoriaId']),
    executionMode: j['modoEjecucion'] == null
        ? ExecutionMode.sequential
        : ExecutionMode.deCable(j['modoEjecucion']),
    athleteMode: j['modoAtletas'] == null
        ? AthleteMode.simultaneous
        : AthleteMode.deCable(j['modoAtletas']),
    timerId: textoOpcional(j['temporizadorId']),
    prescriptions: [
      for (final p in listaJson(j['prescripciones'])) Prescription.fromJson(p),
    ],
  );

  Json toJson() => sinNulos({
    'nombre': name,
    'categoriaId': categoryId,
    'modoEjecucion': executionMode.cable,
    'modoAtletas': athleteMode.cable,
    'temporizadorId': timerId,
    'prescripciones': [for (final p in prescriptions) p.toJson()],
  });
}

/// A training day: optional name plus an ordered list of blocks.
class PlanDay {
  const PlanDay({this.name, this.blocks = const []});

  final String? name;
  final List<PlanBlock> blocks;

  factory PlanDay.fromJson(Json j) => PlanDay(
    name: textoOpcional(j['nombre']),
    blocks: [for (final b in listaJson(j['bloques'])) PlanBlock.fromJson(b)],
  );

  Json toJson() => sinNulos({
    'nombre': name,
    'bloques': [for (final b in blocks) b.toJson()],
  });
}

/// A week model ("A", "B"...): a name plus 1 to 7 days. [id] is unique inside its plan and is what the
/// assignment points to.
class WeekModel {
  const WeekModel({required this.id, required this.name, this.days = const []});

  final String id;
  final String name;
  final List<PlanDay> days;

  factory WeekModel.fromJson(Json j) => WeekModel(
    id: '${j['id']}',
    name: '${j['nombre'] ?? ''}',
    days: [for (final d in listaJson(j['dias'])) PlanDay.fromJson(d)],
  );

  Json toJson() => {
    'id': id,
    'nombre': name,
    'dias': [for (final d in days) d.toJson()],
  };
}

/// A plan: week models plus the 4-position assignment (`weekAssignment[0]` is the week model of week 1).
/// A model can repeat (`A, B, B, A`). The plan repeats in identical cycles; the cycle number lives in the
/// session record, not here.
class Plan implements DelClub {
  const Plan({
    required this.id,
    required this.clubId,
    required this.name,
    this.type = PlanType.regular,
    this.weekModels = const [],
    this.weekAssignment = const [],
    required this.auditoria,
  });

  final String id;
  @override
  final String clubId;
  final String name;
  final PlanType type;
  final List<WeekModel> weekModels;

  /// Ids of [weekModels], one per week of the cycle. Must have [planCycleWeeks] entries.
  final List<String> weekAssignment;
  final Auditoria auditoria;

  /// The week model of the 1-based [week] of the cycle, or null if the assignment does not cover it
  /// or points to a model that does not exist.
  WeekModel? weekModelOf(int week) {
    if (week < 1 || week > weekAssignment.length) return null;
    final id = weekAssignment[week - 1];
    for (final m in weekModels) {
      if (m.id == id) return m;
    }
    return null;
  }

  factory Plan.fromJson(Json j) => Plan(
    id: '${j['id']}',
    clubId: '${j['clubId']}',
    name: '${j['nombre'] ?? ''}',
    type: j['tipo'] == null ? PlanType.regular : PlanType.deCable(j['tipo']),
    weekModels: [
      for (final m in listaJson(j['modelosSemana'])) WeekModel.fromJson(m),
    ],
    weekAssignment: [
      for (final e in (j['asignacion'] as List? ?? const [])) '$e',
    ],
    auditoria: _auditoria(j['auditoria']),
  );

  Json toJson() => {
    'id': id,
    'clubId': clubId,
    'nombre': name,
    'tipo': type.cable,
    'modelosSemana': [for (final m in weekModels) m.toJson()],
    'asignacion': weekAssignment,
    'auditoria': auditoria.toJson(),
  };
}
