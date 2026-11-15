import 'dart:convert';

import 'package:maktub_backend/features/import/history/history_sheets.dart';
import 'package:maktub_backend/features/import/import_report.dart';
import 'package:maktub_backend/features/import/import_run.dart';
import 'package:maktub_backend/features/import/plans/historic_plans.dart';
import 'package:maktub_backend/features/import/plans/plan_import_plan.dart';
import 'package:maktub_core/maktub_core.dart';

/// What the earlier steps resolve for the history: the E8.2 catalog, the E8.3 athletes and the E8.4 plans.
class HistorySources {
  const HistorySources({
    required this.exerciseIdFor,
    required this.athleteIdFor,
    required this.sheetAthletes,
    required this.plans,
    this.pending = const [],
  });

  /// Sheet exercise id → app id (`CatalogPlan.exerciseIdFor`).
  final String? Function(String sheetId) exerciseIdFor;

  /// Sheet athlete id → club athlete id (`AthletePlan.athleteIdFor`).
  final String? Function(String sheetId) athleteIdFor;

  /// Sheet athlete id → name, from Atletas: Tiempos names athletes instead of giving their ids.
  final Map<String, String> sheetAthletes;

  /// Where each Registro row landed ([PlanImportPlan.locate]).
  final PlanImportPlan plans;

  /// The earlier steps that still have work to do. While there is any, nothing is written.
  final List<String> pending;
}

/// What the club has today, the input of [planHistoryImport].
class HistoryState {
  const HistoryState({
    this.plans = const {},
    this.assignments = const [],
    this.groupMembers = const {},
    this.sessions = const [],
    this.records = const [],
    this.blockTimes = const [],
    this.fixedWeights = const [],
  });

  /// The club's plans by app id, with their published version.
  final Map<String, Plan> plans;
  final List<Assignment> assignments;

  /// Group id → athlete ids.
  final Map<String, List<String>> groupMembers;
  final List<Session> sessions;
  final List<SetRecord> records;
  final List<BlockTime> blockTimes;
  final List<FixedWeight> fixedWeights;
}

/// One set to write with E7.3's record-a-set use case.
class PlannedSet {
  const PlannedSet({
    required this.id,
    required this.athleteId,
    required this.blockIndex,
    required this.prescriptionIndex,
    required this.setIndex,
    required this.body,
    required this.line,
    this.sheetRm,
  });

  /// [stableImportId] of the row's natural key; used only if the position has no record yet.
  final String id;
  final String athleteId;
  final int blockIndex;
  final int prescriptionIndex;
  final int setIndex;

  /// The body of `PUT .../sesiones/{id}/registros`.
  final Json body;

  /// The Registro line it comes from.
  final int line;

  /// `rm_vigente` of the row, to compare with the RM the app resolves.
  final double? sheetRm;

  String get position => positionKey(athleteId, blockIndex, prescriptionIndex, setIndex);
}

/// One block time to write with E7.19's record-a-block-time use case.
class PlannedTime {
  const PlannedTime({required this.id, required this.body, required this.line, required this.unchanged});

  final String id;

  /// The body of `PUT .../sesiones/{id}/tiempos/{tiempoId}`.
  final Json body;
  final int line;

  /// Already stored with the same content: not written again.
  final bool unchanged;
}

/// One session of the old app: opened (or resumed) with E7's open-session use case, then its sets and times.
class PlannedSession {
  PlannedSession({
    required this.sheet,
    required this.id,
    required this.assignment,
    required this.week,
    required this.day,
    required this.label,
    this.existing,
  });

  final SheetSessionKey sheet;

  /// [stableImportId] of [sheet]; used only if the session does not exist yet.
  final String id;
  final Assignment assignment;
  final int week;

  /// 1-based day of the week model.
  final int day;
  final String label;

  /// The session already stored under the same key (assignment, date, week, day), if any.
  final Session? existing;
  final present = <String>{};
  final sets = <PlannedSet>[];
  final times = <PlannedTime>[];

  /// Position → what is already stored there.
  final stored = <String, SetRecord>{};

  Json get openBody => {
    'asignacionId': assignment.id,
    'fecha': aIsoFecha(sheet.date),
    'semana': week,
    'dia': day,
    'presentes': present.toList(),
  };
}

/// What the history import has to do.
class HistoryPlan {
  HistoryPlan._() : report = ImportReport('Historial');

  final ImportReport report;
  final sessions = <PlannedSession>[];

  /// An earlier step has work left: nothing may be written.
  bool blocked = false;

  int get setCount => sessions.fold(0, (n, s) => n + s.sets.length);
  int get timeCount => sessions.fold(0, (n, s) => n + s.times.length);
}

String positionKey(String athleteId, int block, int prescription, int set) => '$athleteId|$block|$prescription|$set';

/// Whether two records say the same about a set, whoever wrote them and whenever (like record-a-set does).
bool sameRecordContent(SetRecord a, SetRecord b) {
  String content(SetRecord r) => jsonEncode(
    r.toJson()
      ..remove('id')
      ..remove('auditoria')
      ..remove('escritoPor')
      ..remove('secuencia'),
  );
  return content(a) == content(b);
}

/// The category of the block an old app's Tiempos title names (`reference/Guia.html`, `bloquesDelDia`).
String? _categoryOfTitle(String title) {
  final head = title.split(':').first.trim().toLowerCase();
  return switch (head) {
    'estiramiento' => 'estiramiento',
    'calentamiento' => 'calentamiento',
    'bloque primario' => 'primario',
    'bloque secundario' || 'bloque principal' => 'secundario',
    'bloque accesorios' => 'accesorio',
    _ => null,
  };
}

AthleteMode? _mode(String? sheet) => switch (sheet) {
  null || '' => null,
  'simultaneo' => AthleteMode.simultaneous,
  'turnos' || 'por_turnos' => AthleteMode.turns,
  _ => throw FormatException('modo "$sheet" desconocido'),
};

String _plain(String s) {
  const from = 'áéíóúüñ';
  const to = 'aeiouun';
  final lower = s.trim().toLowerCase();
  return [for (final ch in lower.split('')) from.contains(ch) ? to[from.indexOf(ch)] : ch].join();
}

/// A row that did not resolve, kept with its reason.
class _Skip implements Exception {
  const _Skip(this.reason, {this.expected = false});

  final String reason;

  /// Nothing is lost (the app has nothing to store for it): a notice, not a problem.
  final bool expected;
}

/// Resolves Registro and Tiempos against the club and decides what to write (pure, no I/O):
///
/// - **Session.** Each (date, plan, cycle, week, day) of the sheet is one session of the assignment of the plan
///   imported in E8.4 that covers that date (any status: history includes ended ones). A `historico` row goes to
///   the plan of its month ([historicPlans]), at the position that plan gave it, and its session stays in cycle 1
///   of that plan. Never invents a plan or an assignment: a row whose plan is not in Planes, is still a draft
///   (record-a-set uses the published version), or has no assignment covering the date is reported. For a plan of
///   Planes the cycle the assignment gives the date must be the sheet's; for every row the week's model must be
///   the row's `modelo`.
/// - **Set.** The row is located with [PlanImportPlan.locate] (plan, `modelo`, day, block, `grupo`, `orden`,
///   exercise) and `serie`, and checked against the published plan. The kilos are the sheet's, as typed kilos
///   (`kilosManual`): both percents follow from them and the RM the athlete had that day (E8.3). The target is the
///   published plan's, so October carries the E8.4 correction. `reps` (seconds for an exercise measured in time)
///   and the note, which goes on the exercise's first set, as in the app. A row without kilos is loaded only if the
///   plan would not propose any (no % and no fixed weight): kilos are never invented.
/// - **Time.** Tiempos rows: the block is found by the category its old title names; athlete names are resolved
///   through Atletas; instants come from the sheet's time zone ([sheetLocalToUtc]).
/// - **Ids.** Registro and Tiempos have no ids: sessions, sets and times get a [stableImportId] of their natural
///   key, and the use cases upsert by position (sets), session key (sessions) or id (times), so a re-run
///   overwrites the same documents and never duplicates.
HistoryPlan planHistoryImport(
  HistorySheets sheets,
  HistorySources sources,
  HistoryState state, {
  required String clubId,
}) {
  final out = HistoryPlan._();
  final report = out.report;
  report.problems.addAll(sheets.problems);

  final skipped = <String, List<int>>{};
  final expectedSkips = <String, List<int>>{};
  final timeSkipped = <String, List<int>>{};
  void skip(Map<String, List<int>> into, String reason, int line) => into.putIfAbsent(reason, () => []).add(line);

  final sessions = <String, Object>{}; // sheet key → PlannedSession or _Skip
  final plansById = state.plans;

  PlannedSession session(SheetSessionKey key) {
    final known = sessions[key.key];
    if (known is PlannedSession) return known;
    if (known is _Skip) throw known;
    try {
      final s = _resolveSession(key, sources, state, clubId, plansById);
      sessions[key.key] = s;
      out.sessions.add(s);
      return s;
    } on _Skip catch (e) {
      sessions[key.key] = e;
      rethrow;
    }
  }

  ({PublishedPlan published, List<PlanBlock> blocks}) planDay(PlannedSession s) {
    final published = plansById[s.assignment.planId]!.published!;
    return (published: published, blocks: dayBlocks(published, week: s.week, day: s.day));
  }

  String athleteOf(PlannedSession s, String sheetAthlete, String shown) {
    final id = sources.athleteIdFor(sheetAthlete);
    if (id == null) throw _Skip('el atleta $shown no está vinculado a ningún atleta del club (paso atletas)');
    final a = s.assignment;
    final athletes = a.athleteId != null ? [a.athleteId!] : state.groupMembers[a.groupId] ?? const <String>[];
    if (!athletes.contains(id)) {
      throw _Skip('el atleta $shown no es ${a.isForAthlete ? 'el de la asignación' : 'del grupo de la asignación'}');
    }
    return id;
  }

  // Registro.
  final notes = <String, List<String>>{}; // session|athlete|block|prescription → notes, in row order
  final firstSets = <String, (PlannedSession, PlannedSet)>{};
  final byPosition = <String, (PlannedSession, PlannedSet)>{};
  final repsFromPlan = <int>[];
  final historicCycles = <String, Set<int>>{};
  for (final row in sheets.records) {
    try {
      // A `historico` row goes to its month's plan, at the position that plan gave it.
      var key = row.session;
      var (variant, block, group, order) = (row.variant, row.block, row.group, row.order);
      if (row.session.plan == legacyHistoryPlan) {
        final position = sources.plans.historic.positions[row.line];
        if (position == null) throw const _Skip('la fila "historico" no quedó en ningún plan del mes');
        key = SheetSessionKey(
          date: key.date,
          plan: historicPlanId(key.date),
          cycle: key.cycle,
          week: key.week,
          day: key.day,
        );
        (variant, block, group, order) = (position.variant, position.block, '', position.order);
        historicCycles.putIfAbsent(key.plan, () => {}).add(key.cycle);
      }
      final s = session(key);
      final weekModel = planDay(s).published.weekModelOf(s.week);
      if (weekModel?.id != variant) {
        throw _Skip('la semana ${s.week} del plan es el modelo "${weekModel?.id ?? '-'}" y la fila dice "$variant"');
      }
      final athleteId = athleteOf(s, row.athlete, row.athlete);
      s.present.add(athleteId);
      final exerciseId = sources.exerciseIdFor(row.exercise);
      if (exerciseId == null) throw _Skip('el ejercicio "${row.exercise}" no está en el catálogo');
      final location = sources.plans.locate(
        sheetPlanId: key.plan,
        variant: variant,
        day: key.day,
        block: block,
        group: group,
        order: order,
        exercise: row.exercise,
      );
      if (location == null) {
        throw _Skip(
          'el ejercicio no está en esa posición del plan (bloque, grupo y orden); la app vieja reemplazaba el día '
          'del plan cuando se cambiaba en la sesión',
        );
      }
      final blocks = planDay(s).blocks;
      final prescription =
          location.blockIndex < blocks.length &&
              location.prescriptionIndex < blocks[location.blockIndex].prescriptions.length
          ? blocks[location.blockIndex].prescriptions[location.prescriptionIndex]
          : null;
      if (prescription == null || prescription.exerciseId != exerciseId) {
        throw const _Skip('el plan publicado ya no coincide con la planilla en esa posición');
      }
      final serie = row.set;
      if (serie == null) {
        if (prescription.sets.isEmpty) {
          throw const _Skip(
            'ejercicio sin series en el plan (lista de estiramiento o calentamiento): la app no registra series '
            'ahí, solo el tiempo del bloque',
            expected: true,
          );
        }
        throw const _Skip('la fila no tiene serie');
      }
      final setIndex = location.setIndexOf(serie);
      if (setIndex == null || setIndex >= prescription.sets.length) {
        throw _Skip('la serie $serie no está en el plan');
      }
      final target = prescription.sets[setIndex];
      if (row.kg == null &&
          (target.pct != null ||
              target.kg != null ||
              state.fixedWeights.any((w) => w.athleteId == athleteId && w.exerciseId == exerciseId))) {
        throw const _Skip('no tiene kilos anotados y el plan propondría kilos: no se inventan');
      }

      final inSeconds = target.seconds != null && target.reps == null;
      if (row.reps == null && (target.reps != null || target.seconds != null)) repsFromPlan.add(row.line);
      final body = <String, dynamic>{
        'atletaId': athleteId,
        'bloque': location.blockIndex,
        'prescripcion': location.prescriptionIndex,
        'serie': setIndex,
        'hecha': true,
        if (row.kg != null) ...{'kilosManual': true, 'kilos': row.kg},
        if (row.reps != null) inSeconds ? 'segundos' : 'reps': row.reps,
      };
      final planned = PlannedSet(
        id: stableImportId(clubId, 'serie', [
          row.session.key,
          row.athlete,
          row.block,
          row.group,
          row.order,
          row.exercise,
          serie,
        ]),
        athleteId: athleteId,
        blockIndex: location.blockIndex,
        prescriptionIndex: location.prescriptionIndex,
        setIndex: setIndex,
        body: body,
        line: row.line,
        sheetRm: row.rm,
      );
      final position = '${s.sheet.key}|${planned.position}';
      final previous = byPosition[position];
      if (previous != null) {
        previous.$1.sets.remove(previous.$2);
        report.notes.add(
          'Registro líneas ${previous.$2.line} y ${row.line}: la misma serie dos veces; queda la última, como en la '
          'app vieja.',
        );
      }
      byPosition[position] = (s, planned);
      s.sets.add(planned);
      final exerciseKey = '${s.sheet.key}|$athleteId|${location.blockIndex}|${location.prescriptionIndex}';
      if (row.note != null) notes.putIfAbsent(exerciseKey, () => []).add(row.note!);
      if (setIndex == 0) firstSets[exerciseKey] = (s, planned);
    } on _Skip catch (e) {
      skip(e.expected ? expectedSkips : skipped, e.reason, row.line);
    }
  }
  for (final e in notes.entries) {
    final distinct = e.value.toSet().toList();
    final first = firstSets[e.key];
    if (first == null) {
      report.notes.add('Registro: una nota ("${distinct.first}") no tiene serie 1 donde ir; no se carga.');
      continue;
    }
    first.$2.body['nota'] = distinct.join(' / ');
  }

  // Tiempos.
  final sheetIdByName = <String, List<String>>{};
  sources.sheetAthletes.forEach((id, name) => sheetIdByName.putIfAbsent(_plain(name), () => []).add(id));
  for (final row in sheets.times) {
    try {
      final s = session(row.session);
      final athleteIds = <String>[];
      for (final name in row.athleteNames) {
        final ids = sheetIdByName[_plain(name)] ?? const [];
        if (ids.length != 1) {
          throw _Skip(ids.isEmpty ? 'el atleta "$name" no está en Atletas' : 'hay dos atletas "$name" en Atletas');
        }
        athleteIds.add(athleteOf(s, ids.single, '"$name"'));
      }
      if (athleteIds.isEmpty) throw const _Skip('no tiene atletas');
      final category = _categoryOfTitle(row.block);
      if (category == null) throw _Skip('el bloque "${row.block.split(':').first}" no se reconoce');
      final blocks = planDay(s).blocks;
      final matching = [
        for (var i = 0; i < blocks.length; i++)
          if (blocks[i].categoryId == category) i,
      ];
      if (matching.isEmpty) throw _Skip('el día del plan no tiene bloque de $category');
      if (matching.length > 1 && category == 'accesorio') {
        report.notes.add(
          'Tiempos línea ${row.line}: la app vieja tomaba los accesorios como un solo bloque y el plan los tiene en '
          '${matching.length}; el tiempo queda en el primero.',
        );
      }
      final AthleteMode? mode;
      try {
        mode = _mode(row.mode);
      } on FormatException catch (e) {
        throw _Skip(e.message);
      }
      s.present.addAll(athleteIds);
      final id = stableImportId(clubId, 'tiempo', [row.session.key, row.block, row.start.toIso8601String()]);
      final name = row.block.length > 200 ? row.block.substring(0, 200) : row.block;
      final body = <String, dynamic>{
        'bloque': matching.first,
        'bloqueNombre': name,
        if (mode != null) 'modoAtletas': mode.cable,
        'atletaIds': athleteIds,
        'inicio': row.start.toIso8601String(),
        'fin': row.end.toIso8601String(),
        'interrumpido': row.interrupted,
      };
      final stored = state.blockTimes.where((t) => t.id == id).firstOrNull;
      final unchanged =
          stored != null &&
          stored.blockIndex == matching.first &&
          stored.blockName == name &&
          stored.athleteMode == mode &&
          jsonEncode(stored.athleteIds) == jsonEncode(athleteIds) &&
          stored.start == row.start &&
          stored.end == row.end &&
          stored.interrupted == row.interrupted;
      s.times.add(PlannedTime(id: id, body: body, line: row.line, unchanged: unchanged));
    } on _Skip catch (e) {
      skip(timeSkipped, e.reason, row.line);
    }
  }

  // What is already stored at each position, to tell new from unchanged.
  for (final s in out.sessions) {
    final id = s.existing?.id;
    if (id == null) continue;
    for (final r in state.records.where((r) => r.sessionId == id)) {
      s.stored[positionKey(r.athleteId, r.blockIndex, r.prescriptionIndex, r.setIndex)] = r;
    }
  }

  for (final MapEntry(key: plan, value: cycles) in historicCycles.entries) {
    final others = cycles.where((c) => c != 1).toList()..sort();
    if (others.isNotEmpty) {
      report.notes.add(
        'Registro: el plan $plan tiene filas de ciclo ${others.join(', ')} (archivos de varios meses: el plan se '
        'repetía); acá cada mes es su propio plan y sus sesiones quedan en el ciclo 1.',
      );
    }
  }
  if (repsFromPlan.isNotEmpty) {
    report.notes.add(
      'Registro: ${repsFromPlan.length} series sin reps anotadas quedan con las del plan (líneas '
      '${_lines(repsFromPlan)}).',
    );
  }
  for (final e in skipped.entries) {
    report.problems.add('Registro: ${e.value.length} filas no se importan: ${e.key} (líneas ${_lines(e.value)}).');
  }
  for (final e in expectedSkips.entries) {
    report.notes.add('Registro: ${e.value.length} filas no se cargan: ${e.key} (líneas ${_lines(e.value)}).');
  }
  for (final e in timeSkipped.entries) {
    report.problems.add('Tiempos: ${e.value.length} filas no se importan: ${e.key} (líneas ${_lines(e.value)}).');
  }
  for (final s in out.sessions) {
    if (s.sets.isEmpty && s.times.isEmpty) {
      report.notes.add('${s.label}: no queda ninguna serie ni tiempo para cargar; la sesión no se abre.');
    }
  }
  out.sessions.removeWhere((s) => s.sets.isEmpty && s.times.isEmpty);
  return out;
}

PlannedSession _resolveSession(
  SheetSessionKey key,
  HistorySources sources,
  HistoryState state,
  String clubId,
  Map<String, Plan> plans,
) {
  final planId = sources.plans.planIdOf(key.plan);
  if (planId == null) {
    throw _Skip(
      key.plan == legacyHistoryPlan
          ? 'el plan "historico" no está en Planes: son las filas que la app vieja cargó de la planilla de '
                'planificación (reference/importar.py) y no tienen un plan en la app'
          : 'el plan "${key.plan}" no está en Planes',
    );
  }
  final plan = plans[planId];
  if (plan == null) throw _Skip('el plan "${key.plan}" no está importado (paso planes)');
  final published = plan.published;
  if (published == null) {
    throw _Skip(
      'el plan "${plan.name}" (${key.plan}) está en borrador: la escritura por serie usa la versión publicada',
    );
  }
  final dayIndex = sources.plans.dayIndexOf(key.plan, key.day);
  if (dayIndex == null) throw _Skip('el día ${key.day} del plan "${plan.name}" no está en PlanDias');
  final covering = [
    for (final a in state.assignments)
      if (a.planId == planId && !a.startDate.isAfter(key.date) && (a.endDate == null || !a.endDate!.isBefore(key.date)))
        a,
  ];
  if (covering.isEmpty) {
    throw _Skip(
      'el plan "${plan.name}" no tiene una asignación que cubra la fecha (plans.assignments en ajustes.json; '
      'puede estar terminada)',
    );
  }
  if (covering.length > 1) {
    throw _Skip('el plan "${plan.name}" tiene más de una asignación que cubre la fecha');
  }
  final assignment = covering.single;
  final cycle = UbicacionEnCiclo.desdeFechas(inicio: assignment.startDate, fecha: key.date).ciclo;
  if (cycle != key.cycle && historicMonth(key.plan) == null) {
    throw _Skip(
      'la asignación del plan "${plan.name}" (inicio ${aIsoFecha(assignment.startDate)}) pone la fecha en el '
      'ciclo $cycle y la planilla dice ${key.cycle}',
    );
  }
  final days = published.weekModelOf(key.week)?.days.length ?? 0;
  if (dayIndex >= days) throw _Skip('el día ${key.day} no existe en la semana ${key.week} del plan publicado');
  final existing = state.sessions
      .where(
        (s) => s.assignmentId == assignment.id && s.date == key.date && s.week == key.week && s.day == dayIndex + 1,
      )
      .firstOrNull;
  return PlannedSession(
    sheet: key,
    id: stableImportId(clubId, 'sesion', [key.key]),
    assignment: assignment,
    week: key.week,
    day: dayIndex + 1,
    label: 'sesión ${aIsoFecha(key.date)} · ${plan.name} · ciclo ${key.cycle} semana ${key.week} día ${key.day}',
    existing: existing,
  );
}

String _lines(List<int> lines) {
  if (lines.length <= 6) return lines.join(', ');
  return '${lines.take(5).join(', ')}… (${lines.length})';
}
