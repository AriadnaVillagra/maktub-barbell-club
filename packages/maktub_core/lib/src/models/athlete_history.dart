/// An athlete's history: their past sessions by date, from any plan or assignment (active, ended, historical or
/// deleted), and what they recorded in each (pedido de Ari, 2026-11-21). Read-only. Identifiers are English; the
/// wire stays Spanish like the other contracts.
library;

import '../modelos/json.dart';
import '../modelos/plan.dart';
import '../modelos/sesion.dart';
import '../reglas/fechas.dart';

/// Default and largest page of `GET .../atletas/{atletaId}/historial`.
const defaultHistoryPageSize = 20;
const maxHistoryPageSize = 50;

/// One past session of one athlete, as the history lists it.
class HistoryEntry {
  const HistoryEntry({
    required this.sessionId,
    required this.date,
    required this.assignmentId,
    required this.planId,
    this.planName,
    this.planType,
    required this.cycle,
    required this.week,
    required this.day,
    this.dayName,
    this.done = 0,
    this.total = 0,
    this.estimated = 0,
  });

  final String sessionId;

  /// Calendar date of the session (`DateTime.utc(y, m, d)`).
  final DateTime date;
  final String assignmentId;
  final String planId;

  /// The plan's name, or null when the plan was deleted (E8.9): its sessions and records stay.
  final String? planName;

  /// Null when the plan was deleted.
  final PlanType? planType;
  final int cycle;
  final int week;
  final int day;

  /// The day's name in the plan's published version, if it has one.
  final String? dayName;

  /// Sets the athlete marked done in this session.
  final int done;

  /// Sets of the day: the published plan's planned sets plus any recorded set the plan no longer has. Without the
  /// plan, the athlete's recorded sets.
  final int total;

  /// Sets loaded by the importer with estimated kilos (E8.7), not recorded by anyone.
  final int estimated;

  factory HistoryEntry.fromJson(Json j) => HistoryEntry(
    sessionId: '${j['sesionId']}',
    date: desdeIsoFecha('${j['fecha']}'),
    assignmentId: '${j['asignacionId']}',
    planId: '${j['planId']}',
    planName: textoOpcional(j['planNombre']),
    planType: j['planTipo'] == null ? null : PlanType.deCable(j['planTipo']),
    cycle: enteroOpcional(j['ciclo'])!,
    week: enteroOpcional(j['semana'])!,
    day: enteroOpcional(j['dia'])!,
    dayName: textoOpcional(j['diaNombre']),
    done: enteroOpcional(j['hechas']) ?? 0,
    total: enteroOpcional(j['total']) ?? 0,
    estimated: enteroOpcional(j['estimadas']) ?? 0,
  );

  Json toJson() => {
    'sesionId': sessionId,
    'fecha': aIsoFecha(date),
    'asignacionId': assignmentId,
    'planId': planId,
    ...sinNulos({
      'planNombre': planName,
      'planTipo': planType?.cable,
      'diaNombre': dayName,
    }),
    'ciclo': cycle,
    'semana': week,
    'dia': day,
    'hechas': done,
    'total': total,
    'estimadas': estimated,
  };
}

/// One page of an athlete's history, newest first.
class HistoryPage {
  const HistoryPage({this.entries = const [], this.next});

  final List<HistoryEntry> entries;

  /// The `antesDe` that asks for the next page, or null when there is nothing older. A date is never split
  /// across pages: every session of the oldest date in the page comes in it.
  final DateTime? next;

  factory HistoryPage.fromJson(Json j) => HistoryPage(
    entries: [for (final e in listaJson(j['sesiones'])) HistoryEntry.fromJson(e)],
    next: desdeIsoFechaOpcional(j['siguiente']),
  );

  Json toJson() => {
    'sesiones': [for (final e in entries) e.toJson()],
    ...sinNulos({'siguiente': next == null ? null : aIsoFecha(next!)}),
  };
}

/// One set of an exercise in the history: its target and, if the athlete recorded it, the record.
class HistorySet {
  const HistorySet({required this.index, this.target = const PlanSet(), this.record});

  /// Position of the set in its prescription (0-based).
  final int index;

  /// The target the set had when recorded; for a set not recorded, the published plan's.
  final PlanSet target;

  /// What the athlete did, or null when the set was not recorded. Without the factor and real percent for whoever
  /// cannot see work factors.
  final SetRecord? record;

  factory HistorySet.fromJson(Json j) => HistorySet(
    index: enteroOpcional(j['serie'])!,
    target: PlanSet.fromJson(((j['objetivo'] as Map?) ?? const {}).cast<String, dynamic>()),
    record: j['registro'] == null ? null : SetRecord.fromJson((j['registro'] as Map).cast<String, dynamic>()),
  );

  Json toJson() => {
    'serie': index,
    'objetivo': target.toJson(),
    ...sinNulos({'registro': record?.toJson()}),
  };
}

/// One exercise (a prescription of a block) in the history.
class HistoryExercise {
  const HistoryExercise({
    required this.index,
    required this.exerciseId,
    required this.exerciseName,
    this.sets = const [],
  });

  /// Position of the prescription in its block (0-based).
  final int index;
  final String exerciseId;

  /// The name recorded with the sets; for an exercise with nothing recorded, the catalog's.
  final String exerciseName;
  final List<HistorySet> sets;

  /// The athlete's note on the exercise, which lives on its first set.
  String? get note {
    for (final s in sets) {
      if (s.index == 0) return s.record?.note;
    }
    return null;
  }

  factory HistoryExercise.fromJson(Json j) => HistoryExercise(
    index: enteroOpcional(j['prescripcion'])!,
    exerciseId: '${j['ejercicioId']}',
    exerciseName: '${j['ejercicioNombre'] ?? ''}',
    sets: [for (final s in listaJson(j['series'])) HistorySet.fromJson(s)],
  );

  Json toJson() => {
    'prescripcion': index,
    'ejercicioId': exerciseId,
    'ejercicioNombre': exerciseName,
    'series': [for (final s in sets) s.toJson()],
  };
}

/// One block of the day in the history.
class HistoryBlock {
  const HistoryBlock({
    required this.index,
    this.name,
    this.seconds,
    this.interrupted = false,
    this.exercises = const [],
  });

  /// Position of the block in the day (0-based).
  final int index;

  /// The block's name in the published plan, or the one its time recorded; null when neither is known.
  final String? name;

  /// How long the athlete's runs of the block took in the guided mode (E7.19), added up; null without any.
  final int? seconds;

  /// Whether one of those runs was cut short.
  final bool interrupted;
  final List<HistoryExercise> exercises;

  factory HistoryBlock.fromJson(Json j) => HistoryBlock(
    index: enteroOpcional(j['bloque'])!,
    name: textoOpcional(j['nombre']),
    seconds: enteroOpcional(j['segundos']),
    interrupted: j['interrumpido'] == true,
    exercises: [for (final e in listaJson(j['ejercicios'])) HistoryExercise.fromJson(e)],
  );

  Json toJson() => {
    'bloque': index,
    ...sinNulos({
      'nombre': name,
      'segundos': seconds,
      'interrumpido': interrupted ? true : null,
    }),
    'ejercicios': [for (final e in exercises) e.toJson()],
  };
}

/// One past session as one athlete lived it: its summary, the session's note and the day's blocks.
class SessionHistory {
  const SessionHistory({required this.entry, this.note, this.blocks = const []});

  final HistoryEntry entry;

  /// The session's free note, shared by everyone in it.
  final String? note;
  final List<HistoryBlock> blocks;

  factory SessionHistory.fromJson(Json j) => SessionHistory(
    entry: HistoryEntry.fromJson((j['sesion'] as Map).cast<String, dynamic>()),
    note: textoOpcional(j['nota']),
    blocks: [for (final b in listaJson(j['bloques'])) HistoryBlock.fromJson(b)],
  );

  Json toJson() => {
    'sesion': entry.toJson(),
    ...sinNulos({'nota': note}),
    'bloques': [for (final b in blocks) b.toJson()],
  };
}
