/// Session and per-set record (E7.2; docs/diseno.md, "Sesión y registro").
///
/// A [Session] is the execution of one day of an assignment on a date, with the athletes present. A [SetRecord]
/// is what one athlete did in one set, denormalized on purpose: absolute values, the target the set had, the
/// reference and factor, both percents, the exercise name at the time and the position in the plan. Identifiers
/// are English; the wire (JSON keys and enum values) stays Spanish like the other contracts.
library;

import 'base.dart';
import 'cable.dart';
import 'json.dart';
import 'plan.dart';
import '../reglas/equipo.dart';
import '../reglas/fechas.dart';
import '../reglas/porcentajes.dart';

/// The longest free note, on a session or on an exercise.
const maxNoteLength = 1000;

Auditoria _auditoria(Object? v) =>
    Auditoria.fromJson((v as Map).cast<String, dynamic>());

/// Where an athlete stands on a day of an assignment (diseno, "Sesión y registro").
enum DayStatus implements ConCable {
  /// Not done yet and not decided.
  pending('pendiente'),

  /// Done on its date, in the group session.
  doneOnDate('hecho_en_fecha'),

  /// Done later, outside the group session.
  recovered('recuperado'),

  /// Missed; the coach decided it is not recovered.
  missed('falta');

  const DayStatus(this.cable);
  @override
  final String cable;

  static DayStatus deCable(Object? v) =>
      desdeCable(values, v, 'Estado del día');
}

/// The execution of one day of an assignment on a date. It runs a single plan (the assignment's) and is followed
/// from several devices at once.
class Session implements DelClub {
  const Session({
    required this.id,
    required this.clubId,
    required this.assignmentId,
    required this.planId,
    required this.cycle,
    required this.week,
    required this.day,
    required this.date,
    this.presentAthleteIds = const [],
    this.note,
    this.sequence = 0,
    this.lastSessionChange = 0,
    required this.auditoria,
  });

  final String id;
  @override
  final String clubId;
  final String assignmentId;

  /// The plan the assignment runs. A session executes only this one.
  final String planId;

  /// Cycle number, from 1.
  final int cycle;

  /// Week of the cycle, 1 to 4.
  final int week;

  /// Day within the week's model, 1-based.
  final int day;

  /// Calendar date (`DateTime.utc(y, m, d)`); travels as `yyyy-MM-dd`.
  final DateTime date;

  /// Athletes present, chosen when the session opens among the group's members.
  final List<String> presentAthleteIds;

  /// Free note about the whole session, shared by everyone in it.
  final String? note;

  /// The number of the last change of this session. See [SessionChange].
  final int sequence;

  /// The number of the last change to the session itself (its note or who is present).
  final int lastSessionChange;
  final Auditoria auditoria;

  factory Session.fromJson(Json j) => Session(
    id: '${j['id']}',
    clubId: '${j['clubId']}',
    assignmentId: '${j['asignacionId']}',
    planId: '${j['planId']}',
    cycle: enteroOpcional(j['ciclo'])!,
    week: enteroOpcional(j['semana'])!,
    day: enteroOpcional(j['dia'])!,
    date: desdeIsoFecha('${j['fecha']}'),
    presentAthleteIds: [
      for (final a in (j['presentes'] as List? ?? const [])) '$a',
    ],
    note: textoOpcional(j['nota']),
    sequence: enteroOpcional(j['secuencia']) ?? 0,
    lastSessionChange: enteroOpcional(j['secuenciaSesion']) ?? 0,
    auditoria: _auditoria(j['auditoria']),
  );

  Json toJson() => {
    'id': id,
    'clubId': clubId,
    'asignacionId': assignmentId,
    'planId': planId,
    'ciclo': cycle,
    'semana': week,
    'dia': day,
    'fecha': aIsoFecha(date),
    'presentes': presentAthleteIds,
    ...sinNulos({'nota': note}),
    'secuencia': sequence,
    'secuenciaSesion': lastSessionChange,
    'auditoria': auditoria.toJson(),
  };
}

/// The state of one day of an assignment for one athlete. Missing document means [DayStatus.pending].
class AthleteDay implements DelClub {
  const AthleteDay({
    required this.id,
    required this.clubId,
    required this.assignmentId,
    required this.athleteId,
    required this.cycle,
    required this.week,
    required this.day,
    this.status = DayStatus.pending,
    this.date,
    this.sessionId,
    required this.auditoria,
  });

  final String id;
  @override
  final String clubId;
  final String assignmentId;
  final String athleteId;
  final int cycle;
  final int week;
  final int day;
  final DayStatus status;

  /// Calendar date it was done on (or recovered on); null while pending or missed.
  final DateTime? date;

  /// The group session it was done in; null for a recovered day or one not done.
  final String? sessionId;
  final Auditoria auditoria;

  factory AthleteDay.fromJson(Json j) => AthleteDay(
    id: '${j['id']}',
    clubId: '${j['clubId']}',
    assignmentId: '${j['asignacionId']}',
    athleteId: '${j['atletaId']}',
    cycle: enteroOpcional(j['ciclo'])!,
    week: enteroOpcional(j['semana'])!,
    day: enteroOpcional(j['dia'])!,
    status: DayStatus.deCable(j['estado']),
    date: desdeIsoFechaOpcional(j['fecha']),
    sessionId: textoOpcional(j['sesionId']),
    auditoria: _auditoria(j['auditoria']),
  );

  Json toJson() => {
    'id': id,
    'clubId': clubId,
    'asignacionId': assignmentId,
    'atletaId': athleteId,
    'ciclo': cycle,
    'semana': week,
    'dia': day,
    'estado': status.cable,
    ...sinNulos({
      'fecha': date == null ? null : aIsoFecha(date!),
      'sesionId': sessionId,
    }),
    'auditoria': auditoria.toJson(),
  };
}

/// The two percents of a record: of the plan (before the factor) and the real one (`factor × plan`).
class RecordPcts {
  const RecordPcts({required this.pctPlan, required this.pctReal});

  /// Percent of the RM the plan prescribed, or the one that follows from typed kilos.
  final double pctPlan;

  /// `workFactor × pctPlan / 100`: the percent of the RM actually lifted.
  final double pctReal;

  /// From a plan percent: the real one applies the work factor (a percent, 80 = 80 %; 100 is neutral).
  factory RecordPcts.fromPlan(double pctPlan, {double workFactor = 100}) =>
      RecordPcts(
        pctPlan: pctPlan,
        pctReal: (pctPlan * workFactor).round() / 100,
      );

  /// From kilos the athlete typed by hand: both percents come from them, so `rm × pctReal ≈ kg` holds.
  /// Null without a usable RM or factor (see [pctDesdePeso]).
  static RecordPcts? fromWeight(
    double kg,
    double? rm, {
    double workFactor = 100,
  }) {
    final plan = pctDesdePeso(kg, rm, workFactor: workFactor);
    if (plan == null) return null;
    return RecordPcts(
      pctPlan: plan,
      pctReal: (rm! > 0 ? (kg / rm * 10000).round() / 100 : plan),
    );
  }
}

/// What one athlete did in one set. One entry per athlete, exercise and set (the position identifies it).
class SetRecord implements DelClub {
  const SetRecord({
    required this.id,
    required this.clubId,
    required this.sessionId,
    required this.athleteId,
    required this.exerciseId,
    required this.exerciseName,
    required this.blockIndex,
    required this.prescriptionIndex,
    required this.setIndex,
    this.target = const PlanSet(),
    this.done = true,
    this.kg,
    this.reps,
    this.seconds,
    this.distanceM,
    this.calories,
    this.referenceId,
    this.referenceValue,
    this.workFactor,
    this.pctPlan,
    this.pctReal,
    this.rpe,
    this.manualKg = false,
    this.note,
    this.sequence,
    required this.writtenBy,
    required this.auditoria,
  });

  final String id;
  @override
  final String clubId;
  final String sessionId;
  final String athleteId;
  final String exerciseId;

  /// The exercise's name when it was recorded; renaming it later does not change history.
  final String exerciseName;

  /// Position in the plan: block, prescription within the block, set within the prescription (all 0-based).
  final int blockIndex;
  final int prescriptionIndex;
  final int setIndex;

  /// The target the set had, kept next to what was done to measure difficulty without rebuilding the plan.
  final PlanSet target;

  /// Whether the athlete marked the set done.
  final bool done;

  /// Absolute values done. Each is null when its metric does not apply.
  final double? kg;
  final int? reps;
  final int? seconds;
  final double? distanceM;
  final double? calories;

  /// Id of the reference (RM, mark, pace) used and its value at the time, so history never points at
  /// something that changes meaning.
  final String? referenceId;
  final double? referenceValue;

  /// Work factor applied, as a percent (80 = 80 %); null when there was none.
  final double? workFactor;

  /// Percent of the plan and real percent, `pctReal = workFactor × pctPlan`. See [RecordPcts].
  final double? pctPlan;
  final double? pctReal;

  /// Perceived effort normalized as RPE (6 to 10, halves allowed), if loaded. M1 has no capture for it.
  final double? rpe;

  /// The athlete typed the kilos by hand, so the percents come from them.
  final bool manualKg;

  /// Free note about the exercise. It lives on the exercise's first set (`setIndex` 0).
  final String? note;

  /// The number of the session's change that last modified this record. Null if it came from outside the live flow.
  final int? sequence;

  /// Id of the user who wrote it, which may be a coach writing for the athlete.
  final String writtenBy;
  final Auditoria auditoria;

  factory SetRecord.fromJson(Json j) => SetRecord(
    id: '${j['id']}',
    clubId: '${j['clubId']}',
    sessionId: '${j['sesionId']}',
    athleteId: '${j['atletaId']}',
    exerciseId: '${j['ejercicioId']}',
    exerciseName: '${j['ejercicioNombre']}',
    blockIndex: enteroOpcional(j['bloque'])!,
    prescriptionIndex: enteroOpcional(j['prescripcion'])!,
    setIndex: enteroOpcional(j['serie'])!,
    target: PlanSet.fromJson(
      ((j['objetivo'] as Map?) ?? const {}).cast<String, dynamic>(),
    ),
    done: j['hecha'] != false,
    kg: numOpcional(j['kilos']),
    reps: enteroOpcional(j['reps']),
    seconds: enteroOpcional(j['segundos']),
    distanceM: numOpcional(j['distanciaM']),
    calories: numOpcional(j['calorias']),
    referenceId: textoOpcional(j['referenciaId']),
    referenceValue: numOpcional(j['referenciaValor']),
    workFactor: numOpcional(j['factor']),
    pctPlan: numOpcional(j['pctPlan']),
    pctReal: numOpcional(j['pctReal']),
    rpe: numOpcional(j['rpe']),
    manualKg: j['kilosManual'] == true,
    note: textoOpcional(j['nota']),
    sequence: enteroOpcional(j['secuencia']),
    writtenBy: '${j['escritoPor']}',
    auditoria: _auditoria(j['auditoria']),
  );

  Json toJson() => {
    'id': id,
    'clubId': clubId,
    'sesionId': sessionId,
    'atletaId': athleteId,
    'ejercicioId': exerciseId,
    'ejercicioNombre': exerciseName,
    'bloque': blockIndex,
    'prescripcion': prescriptionIndex,
    'serie': setIndex,
    'objetivo': target.toJson(),
    'hecha': done,
    ...sinNulos({
      'kilos': kg,
      'reps': reps,
      'segundos': seconds,
      'distanciaM': distanceM,
      'calorias': calories,
      'referenciaId': referenceId,
      'referenciaValor': referenceValue,
      'factor': workFactor,
      'pctPlan': pctPlan,
      'pctReal': pctReal,
      'rpe': rpe,
      'kilosManual': manualKg ? true : null,
      'nota': note,
      'secuencia': sequence,
    }),
    'escritoPor': writtenBy,
    'auditoria': auditoria.toJson(),
  };
}

/// One change of a session, numbered within it from 1. A record or a session carries its whole current state, so
/// applying a change twice is harmless. The numbers can skip: a client only remembers the highest it has seen.
class SessionChange {
  const SessionChange.ofRecord(this.sequence, SetRecord this.record)
    : session = null;
  const SessionChange.ofSession(this.sequence, Session this.session)
    : record = null;

  final int sequence;
  final SetRecord? record;
  final Session? session;

  String get clubId => record?.clubId ?? session!.clubId;
  String get sessionId => record?.sessionId ?? session!.id;

  factory SessionChange.fromJson(Json j) {
    final sequence = enteroOpcional(j['secuencia'])!;
    return j['tipo'] == 'sesion'
        ? SessionChange.ofSession(
            sequence,
            Session.fromJson((j['sesion'] as Map).cast<String, dynamic>()),
          )
        : SessionChange.ofRecord(
            sequence,
            SetRecord.fromJson((j['registro'] as Map).cast<String, dynamic>()),
          );
  }

  Json toJson() => {
    'secuencia': sequence,
    if (record != null) ...{
      'tipo': 'registro',
      'registro': record!.toJson(),
    } else ...{
      'tipo': 'sesion',
      'sesion': session!.toJson(),
    },
  };
}

/// The proposed kilos of one set of the session, as the server resolves them for one athlete (it travels without
/// the athlete's work factor unless the viewer can see references).
class ProposedSet {
  const ProposedSet({
    required this.blockIndex,
    required this.prescriptionIndex,
    required this.setIndex,
    required this.exerciseId,
    this.kg,
    this.appliedPct,
    this.workFactor,
  });

  /// Position in the plan, as in [SetRecord] (all 0-based).
  final int blockIndex;
  final int prescriptionIndex;
  final int setIndex;
  final String exerciseId;

  /// Empty, never zero, when there is nothing to propose.
  final double? kg;

  /// The plan's percent with the day's adjustment, if the set has one.
  final double? appliedPct;

  /// The work factor applied (a percent), only when it is not neutral and the viewer can see it.
  final double? workFactor;

  factory ProposedSet.fromJson(Json j) => ProposedSet(
    blockIndex: enteroOpcional(j['bloque'])!,
    prescriptionIndex: enteroOpcional(j['prescripcion'])!,
    setIndex: enteroOpcional(j['serie'])!,
    exerciseId: '${j['ejercicioId']}',
    kg: numOpcional(j['kilos']),
    appliedPct: numOpcional(j['pctAplicado']),
    workFactor: numOpcional(j['factor']),
  );

  Json toJson() => {
    'bloque': blockIndex,
    'prescripcion': prescriptionIndex,
    'serie': setIndex,
    'ejercicioId': exerciseId,
    ...sinNulos({
      'kilos': kg,
      'pctAplicado': appliedPct,
      'factor': workFactor,
    }),
  };
}

/// The weight the plan proposes for a percent set, with both percents, using the E4.1 rule.
/// Convenience for tests and the slices; null without a usable RM.
({double kg, RecordPcts pcts})? proposedFromPlan({
  required double? rm,
  required double pctPlan,
  required Equipo equipo,
  double workFactor = 100,
}) {
  final kg = pesoPorPorcentaje(
    rm: rm,
    pct: pctPlan,
    equipo: equipo,
    workFactor: workFactor,
  );
  if (kg == null) return null;
  return (kg: kg, pcts: RecordPcts.fromPlan(pctPlan, workFactor: workFactor));
}
