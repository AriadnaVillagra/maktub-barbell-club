import 'dart:convert';

import 'package:maktub_backend/features/import/grid/grid_sheet.dart';
import 'package:maktub_backend/features/import/import_report.dart';
import 'package:maktub_backend/features/import/import_run.dart';
import 'package:maktub_core/maktub_core.dart';

/// The `planningGrid` section of `tool/importar/ajustes.json`: which grid becomes which plan, who did it and when.
class GridAdjustments {
  const GridAdjustments({
    required this.sheet,
    required this.planKey,
    required this.planName,
    required this.group,
    required this.months,
    this.absent = const [],
    this.exerciseNames = const {},
  });

  /// Null when the section is missing (the step has nothing to do).
  static GridAdjustments? fromRaw(Map<String, dynamic> raw) {
    final j = (raw['planningGrid'] as Map?)?.cast<String, dynamic>();
    if (j == null) return null;
    final plan = (j['plan'] as Map).cast<String, dynamic>();
    return GridAdjustments(
      sheet: '${j['sheet']}',
      planKey: '${plan['id']}',
      planName: '${plan['name']}',
      group: '${j['group']}',
      months: [for (final m in j['months'] as List) desdeIsoFecha('$m-01')],
      absent: [
        for (final a in (j['absent'] as List? ?? const []))
          for (final e in [(a as Map).cast<String, dynamic>()])
            GridAbsence(
              month: desdeIsoFecha('${e['month']}-01'),
              week: (e['week'] as num).toInt(),
              day: (e['day'] as num).toInt(),
              athlete: '${e['athlete']}',
            ),
      ],
      exerciseNames: {
        for (final e in ((j['exerciseNames'] as Map?) ?? const {}).entries)
          if (!'${e.key}'.startsWith('_')) plainName('${e.key}'): '${e.value}',
      },
    );
  }

  /// The grid's file name in the planning folder, without `.csv`.
  final String sheet;

  /// The plan's key: its id is [importedId] of it.
  final String planKey;
  final String planName;

  /// The club group that did it.
  final String group;

  /// The first day of each month the plan was repeated in, one cycle per month.
  final List<DateTime> months;

  /// Athletes who missed a day.
  final List<GridAbsence> absent;

  /// Grid name ([plainName]) → sheet exercise id (resolved through E8.2) or app exercise id.
  final Map<String, String> exerciseNames;

  DateTime get from => months.first;
  DateTime get to => DateTime.utc(months.last.year, months.last.month + 1, 0);
}

/// An athlete who missed one day of one week of one month.
class GridAbsence {
  const GridAbsence({required this.month, required this.week, required this.day, required this.athlete});

  final DateTime month;
  final int week;
  final int day;

  /// Display name.
  final String athlete;
}

/// What the grid step needs from the catalog: E8.2's id map, the club's exercises and the old sheet's names.
class GridCatalog {
  const GridCatalog({required this.exerciseIdFor, required this.exercises, this.sheetNames = const {}});

  /// Sheet exercise id → app id (`CatalogPlan.exerciseIdFor`).
  final String? Function(String sheetId) exerciseIdFor;

  /// App exercises visible to the club, by id.
  final Map<String, Exercise> exercises;

  /// [plainName] of an Ejercicios name → its sheet id.
  final Map<String, String> sheetNames;
}

/// What the club has today, the input of [planGridImport].
class GridState {
  const GridState({
    this.plan,
    this.assignment,
    this.groups = const [],
    this.athletes = const {},
    this.sessions = const [],
    this.records = const [],
    this.references = const [],
    this.factors = const [],
    this.fixedWeights = const [],
    this.equipment,
  });

  /// The plan with the grid plan's id, if it exists.
  final Plan? plan;

  /// The assignment with the grid assignment's id, if it exists.
  final Assignment? assignment;
  final List<AthleteGroup> groups;

  /// Club athletes by id.
  final Map<String, Atleta> athletes;

  /// The sessions of [assignment].
  final List<Session> sessions;

  /// The records of [sessions].
  final List<SetRecord> records;
  final List<Reference> references;
  final List<WorkFactor> factors;
  final List<FixedWeight> fixedWeights;
  final Equipo? equipment;
}

/// One estimated set to write with E7.3's record-a-set use case, in estimate mode.
class EstimatedSet {
  const EstimatedSet({required this.id, required this.body, required this.kg, this.stored});

  /// Used only if the position has no record yet.
  final String id;

  /// The body of `PUT .../sesiones/{id}/registros`, with `estimada: true` and no kilos: the use case computes them.
  final Json body;

  /// The kilos the app proposes, as computed here (the use case computes the same).
  final double? kg;

  /// The estimated record already there, if any.
  final SetRecord? stored;
}

/// One session of the plan: opened (or resumed) with E7's open-session use case, then its estimated sets.
class EstimatedSession {
  EstimatedSession({required this.id, required this.label, required this.openBody, this.existing});

  final String id;
  final String label;

  /// The body of `POST .../sesiones`.
  final Json openBody;
  final Session? existing;
  final sets = <EstimatedSet>[];

  /// Sets corrected in the app since: never written again.
  var kept = 0;
}

/// What the grid step has to do.
class GridImportPlan {
  GridImportPlan._(this.plan) : report = ImportReport('Abril 2026 (series estimadas)');

  final ImportReport report;

  /// The plan the grid describes.
  final Plan plan;

  /// Created, saved and (when [publishable]) published.
  bool createPlan = false;

  /// Already saved like the grid but never published: published now.
  bool publishPlan = false;
  bool publishable = false;

  /// The assignment to create, with E6's create body; null when it exists or cannot be created.
  Json? assignmentBody;
  String? assignmentId;
  final sessions = <EstimatedSession>[];

  /// Something stops the sessions from being written (the plan or the assignment differ).
  bool blocked = false;

  /// An earlier step has work left: nothing may be written.
  bool pending = false;

  int get setCount => sessions.fold(0, (n, s) => n + s.sets.length);
}

/// Lowercase, without accents and with single spaces: how grid names are compared.
String plainName(String s) {
  const from = 'áéíóúüñ';
  const to = 'aeiouun';
  final lower = s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  return [for (final ch in lower.split('')) from.contains(ch) ? to[from.indexOf(ch)] : ch].join();
}

/// The reps of a grid's sets column, one per set, and what follows them: `4X6` → 6 × 4; `10/10/8/6/4/2`;
/// `7/2x5/3x3` → 7, 5, 5, 3, 3, 3; `3x10 c/lado` → 10 × 3 and `c/lado`. Null if it has no sets.
({List<int> reps, String rest})? parseGridSets(String text) {
  final t = text.trim().toLowerCase();
  final spec = RegExp(r'^[\d\sx/]+').firstMatch(t)?.group(0) ?? '';
  final reps = <int>[];
  for (final part in spec.split('/')) {
    final p = part.trim();
    if (p.isEmpty) continue;
    final uniform = RegExp(r'^(\d+)\s*x\s*(\d+)$').firstMatch(p);
    if (uniform != null) {
      reps.addAll(List.filled(int.parse(uniform.group(1)!), int.parse(uniform.group(2)!)));
    } else if (RegExp(r'^\d+$').hasMatch(p)) {
      reps.add(int.parse(p));
    } else {
      return null;
    }
  }
  if (reps.isEmpty) return null;
  return (reps: reps, rest: text.trim().substring(spec.length).trim());
}

/// What a grid's load column says: a % (`0.65` → 65, with E4's normalization), kilos (`mancuerna 12kg`), the bar
/// (`barra de 20`) and the text as a note when it is not just a %. Never a number the cell does not write.
({double? pct, double? kg, double? barKg, String? note}) parseGridLoad(String text) {
  final t = text.trim();
  if (t.isEmpty) return (pct: null, kg: null, barKg: null, note: null);
  final number = double.tryParse(t.replaceAll(',', '.'));
  if (number != null) return (pct: normalizarPct(number), kg: null, barKg: null, note: null);
  final kg = RegExp(r'(\d+(?:[.,]\d+)?)\s*kg\b', caseSensitive: false).firstMatch(t);
  final bar = RegExp(r'^barra de (\d+(?:[.,]\d+)?)$', caseSensitive: false).firstMatch(t);
  return (
    pct: null,
    kg: kg == null ? null : double.parse(kg.group(1)!.replaceAll(',', '.')),
    barKg: bar == null ? null : double.parse(bar.group(1)!.replaceAll(',', '.')),
    note: t,
  );
}

const _categoryOrder = ['primario', 'secundario', 'accesorio', 'calentamiento', 'estiramiento'];
const _categoryNames = {
  'primario': 'Primario',
  'secundario': 'Secundario',
  'accesorio': 'Accesorios',
  'calentamiento': 'Calentamiento',
  'estiramiento': 'Estiramiento',
};

/// The stable id of the grid plan's assignment.
String gridAssignmentId(String clubId, GridAdjustments adj) =>
    importedId(clubId, 'asignacion-${adj.planKey}-${aIsoFecha(adj.from)}');

/// Decides what the grid step writes (pure, no I/O):
///
/// - **Plan.** A [PlanType.history] plan named [GridAdjustments.planName]: one week model per grid week (`s1`..`s4`)
///   and the four in order; its days are the grid's `DIA n`. Each grid block becomes a block: the warm-up, `BLOQUE n`
///   and the WOD (category `wod`, its text as the note and the exercises it names). A block takes the first category
///   all its exercises share; if they share none it is split by category (D16: a block holds its category's
///   exercises). Sets are the grid's reps, with its % (`0.65` → 65) or kilos (`12kg`); any other load text (`barra de
///   15/20`, `con barra`) goes to the prescription's note, and `barra de N` also to its bar. Mobility, rest and
///   remarks go to the block's note. A name that does not resolve to the catalog is reported and left out, never
///   invented. An existing plan is never overwritten.
/// - **Assignment.** One ended assignment of the plan for [GridAdjustments.group], from the first day of the first
///   month to the last of the last one, created like E8.5's.
/// - **Sessions.** Week *s*, day *d* of each month is its day `7·(s−1)+d`, like the migrated history; present are the
///   group's athletes minus [GridAdjustments.absent].
/// - **Sets.** Every set of the day for each present athlete, marked done and **estimated**, with the kilos the app
///   proposes on that date (E4: RM × work factor × %, else the athlete's fixed weight, else the grid's kilos, rounded
///   to a loadable weight; [proposedDaySets]). A set of an exercise measured by load that gets no kilos (no RM, no %,
///   no fixed weight) is reported and not loaded. A set already recorded and no longer estimated (corrected in the
///   app) is never written again.
GridImportPlan planGridImport(
  PlanningGrid grid,
  GridAdjustments adj,
  GridCatalog catalog,
  GridState state, {
  required String clubId,
  required DateTime now,
}) {
  final built = _PlanBuilder(grid, adj, catalog, clubId, now).build();
  final out = GridImportPlan._(built.plan);
  final report = out.report;
  final plan = built.plan;
  report.problems.addAll(built.problems);
  report.notes.addAll(built.notes);
  if (grid.skippedRows.isNotEmpty) {
    report.notes.add('${grid.skippedRows.length} filas marcadas "no hicimos esto" no entran (filas ${grid.skippedRows.join(', ')}).');
  }
  for (final i in grid.ignored) {
    report.notes.add('Celda ignorada: $i.');
  }

  // Plan.
  final label = 'plan "${plan.name}" (${adj.sheet})';
  final validation = validatePlan(plan, exerciseById: (id) => catalog.exercises[id]);
  out.publishable = validation.isEmpty;
  if (!out.publishable) {
    report.problems.add(
      '$label no se puede publicar (${validation.length} problemas: '
      '${{for (final p in validation) p.code.name}.join(', ')}); queda en borrador y no se cargan sesiones.',
    );
    out.blocked = true;
  }
  final stored = state.plan;
  PublishedPlan? published;
  if (stored == null) {
    out.createPlan = true;
    report.created.add('$label: ${_summary(plan)}; ${out.publishable ? 'se publica (modo historial)' : 'queda en borrador'}.');
    published = PublishedPlan(
      weekModels: plan.weekModels,
      weekAssignment: plan.weekAssignment,
      publishedAt: now,
      publishedBy: importAuthor,
    );
  } else {
    final same = _content(stored.weekModels, stored.weekAssignment) == _content(plan.weekModels, plan.weekAssignment) &&
        stored.name.trim() == plan.name.trim() &&
        stored.type == plan.type;
    if (!same) report.differing.add('$label: ya existe y no coincide con la grilla; no se toca.');
    final storedPublished = stored.published;
    if (storedPublished == null) {
      if (same && out.publishable) {
        out.publishPlan = true;
        report.updated.add('$label: guardado igual a la grilla pero sin publicar; se publica.');
        published = PublishedPlan(
          weekModels: plan.weekModels,
          weekAssignment: plan.weekAssignment,
          publishedAt: now,
          publishedBy: importAuthor,
        );
      }
    } else if (_content(storedPublished.weekModels, storedPublished.weekAssignment) ==
        _content(plan.weekModels, plan.weekAssignment)) {
      published = storedPublished;
      if (same) report.unchanged.add(label);
    }
    if (published == null) {
      report.problems.add('$label: la versión publicada no es la de la grilla; no se cargan sesiones.');
      out.blocked = true;
    }
  }

  // Assignment.
  final groups = state.groups.where((g) => plainName(g.name) == plainName(adj.group)).toList();
  if (groups.length != 1) {
    report.problems.add(
      '${groups.isEmpty ? 'No hay un grupo "${adj.group}"' : 'Hay ${groups.length} grupos "${adj.group}"'} en el club: '
      'no se asigna ni se cargan sesiones.',
    );
    out.blocked = true;
    return out;
  }
  final group = groups.single;
  final assignmentId = gridAssignmentId(clubId, adj);
  out.assignmentId = assignmentId;
  final assignmentLabel =
      'asignación de "${plan.name}" al grupo "${group.name}" (${aIsoFecha(adj.from)} a ${aIsoFecha(adj.to)})';
  final assignment = state.assignment;
  if (assignment == null) {
    out.assignmentBody = {
      'planId': plan.id,
      'grupoId': group.id,
      'fechaInicio': aIsoFecha(adj.from),
      'fechaFin': aIsoFecha(adj.to),
    };
    report.created.add('$assignmentLabel: terminada.');
  } else if (assignment.planId == plan.id &&
      assignment.groupId == group.id &&
      assignment.startDate == adj.from &&
      assignment.endDate == adj.to) {
    report.unchanged.add(assignmentLabel);
  } else {
    report.differing.add('$assignmentLabel: ya existe y no coincide; no se toca ni se cargan sesiones.');
    out.blocked = true;
  }

  // Athletes.
  final members = [for (final id in group.memberIds) ?state.athletes[id]];
  Atleta? athleteNamed(String name) {
    final found = members.where((a) => plainName(a.nombreVisible) == plainName(name)).toList();
    return found.length == 1 ? found.single : null;
  }

  final absentIds = <String, Set<String>>{}; // date → athlete ids
  for (final a in adj.absent) {
    final athlete = athleteNamed(a.athlete);
    if (athlete == null) {
      report.problems.add('planningGrid.absent: "${a.athlete}" no es un atleta del grupo "${group.name}".');
      continue;
    }
    absentIds.putIfAbsent(aIsoFecha(_dateOf(a.month, a.week, a.day)), () => {}).add(athlete.id);
  }
  for (final MapEntry(key: key, value: remark) in grid.dayRemarks.entries) {
    final [day, week] = key.split('|');
    report.notes.add(
      'La grilla dice en el día $day de la semana $week: "$remark" (planningGrid.absent decide quién falta y qué mes).',
    );
  }

  // RMs of the grid against the app's.
  _compareRms(grid, adj, catalog, state, report, athleteNamed);

  if (published == null) return out;

  // Sessions and sets.
  final exercises = catalog.exercises;
  final equipo = state.equipment ?? Equipo.estandarDe(clubId);
  final fixedByAthlete = <String, Map<String, double>>{};
  for (final w in state.fixedWeights) {
    fixedByAthlete.putIfAbsent(w.athleteId, () => {})[w.exerciseId] = w.kg;
  }
  final skipped = <String, (int, Set<String>)>{};
  final otherCycle = <String>[];
  var kept = 0;
  for (var m = 0; m < adj.months.length; m++) {
    final month = adj.months[m];
    for (var w = 1; w <= planCycleWeeks; w++) {
      final days = published.weekModelOf(w)?.days ?? const <PlanDay>[];
      final dayNumbers = built.dayNumbers;
      for (var i = 0; i < days.length && i < dayNumbers.length; i++) {
        final date = _dateOf(month, w, dayNumbers[i]);
        if (date.month != month.month) continue;
        final present = [
          for (final a in members)
            if (!(absentIds[aIsoFecha(date)] ?? const {}).contains(a.id)) a,
        ];
        final cycle = UbicacionEnCiclo.desdeFechas(inicio: adj.from, fecha: date).ciclo;
        if (cycle != m + 1) otherCycle.add('${aIsoFecha(date)} (ciclo $cycle)');
        final existing = state.sessions
            .where((s) => s.assignmentId == assignmentId && s.date == date && s.week == w && s.day == i + 1)
            .firstOrNull;
        final session = EstimatedSession(
          id: stableImportId(clubId, 'sesion-estimada', [adj.planKey, aIsoFecha(date), w, i + 1]),
          label: 'sesión ${aIsoFecha(date)} · semana $w día ${dayNumbers[i]}',
          openBody: {
            'asignacionId': assignmentId,
            'fecha': aIsoFecha(date),
            'semana': w,
            'dia': i + 1,
            'presentes': [for (final a in present) a.id],
          },
          existing: existing,
        );
        final blocks = days[i].blocks;
        for (final athlete in present) {
          final proposed = proposedDaySets(
            blocks: blocks,
            exercises: exercises,
            athleteId: athlete.id,
            on: date,
            references: state.references,
            factors: state.factors,
            fixedKg: fixedByAthlete[athlete.id] ?? const {},
            equipo: equipo,
          );
          for (final p in proposed) {
            final exercise = exercises[p.exerciseId];
            final prescription = blocks[p.blockIndex].prescriptions[p.prescriptionIndex];
            final target = prescription.sets[p.setIndex];
            if (exercise == null) continue;
            if (exercise.metrics.any((m) => m.isLoad) && p.kg == null) {
              final why = target.pct != null
                  ? 'sin RM vigente de ${exercises[rmExerciseIdFor(exercise, exercises)]?.name ?? 'su ejercicio de referencia'}'
                  : 'sin % ni kilos en la grilla y sin kilaje fijo del atleta';
              final key = '${exercise.name}${prescription.note == null ? '' : ' ("${prescription.note}")'}: $why';
              final (n, who) = skipped[key] ?? (0, <String>{});
              skipped[key] = (n + 1, who..add(athlete.nombreVisible));
              continue;
            }
            final stored = existing == null
                ? null
                : state.records
                      .where(
                        (r) =>
                            r.sessionId == existing.id &&
                            r.athleteId == athlete.id &&
                            r.blockIndex == p.blockIndex &&
                            r.prescriptionIndex == p.prescriptionIndex &&
                            r.setIndex == p.setIndex,
                      )
                      .firstOrNull;
            if (stored != null && !stored.estimated) {
              session.kept++;
              kept++;
              continue;
            }
            session.sets.add(
              EstimatedSet(
                id: stableImportId(clubId, 'serie-estimada', [
                  adj.planKey,
                  aIsoFecha(date),
                  athlete.id,
                  p.blockIndex,
                  p.prescriptionIndex,
                  p.setIndex,
                ]),
                body: {
                  'atletaId': athlete.id,
                  'bloque': p.blockIndex,
                  'prescripcion': p.prescriptionIndex,
                  'serie': p.setIndex,
                  'hecha': true,
                  'estimada': true,
                },
                kg: p.kg,
                stored: stored,
              ),
            );
          }
        }
        if (session.sets.isNotEmpty || session.kept > 0) out.sessions.add(session);
      }
    }
  }
  for (final MapEntry(key: what, value: (n, who)) in skipped.entries) {
    report.problems.add('$n series no se cargan: $what (${who.join(', ')}).');
  }
  if (kept > 0) {
    report.notes.add('$kept series ya corregidas en la app (no estimadas): no se tocan.');
  }
  if (otherCycle.isNotEmpty) {
    report.notes.add(
      'Una sola asignación desde ${aIsoFecha(adj.from)} pone ${otherCycle.length} sesiones en un ciclo distinto del '
      'número de mes (los ciclos son de 28 días): ${otherCycle.take(5).join(', ')}'
      '${otherCycle.length > 5 ? '…' : ''}. La semana de cada sesión es la de la grilla.',
    );
  }
  return out;
}

DateTime _dateOf(DateTime month, int week, int day) => DateTime.utc(month.year, month.month, 7 * (week - 1) + day);

void _compareRms(
  PlanningGrid grid,
  GridAdjustments adj,
  GridCatalog catalog,
  GridState state,
  ImportReport report,
  Atleta? Function(String name) athleteNamed,
) {
  var same = 0;
  for (final rm in grid.rms) {
    final where = 'KG RM de la grilla (fila ${rm.row}): ${rm.athlete} ${rm.exercise} ${_fmt(rm.kg)}';
    final athlete = athleteNamed(rm.athlete);
    final exerciseId = _resolve(rm.exercise, adj, catalog);
    final exercise = exerciseId == null ? null : catalog.exercises[exerciseId];
    final rmExerciseId = exercise == null ? null : rmExerciseIdFor(exercise, catalog.exercises);
    if (athlete == null || rmExerciseId == null) {
      report.notes.add('$where: ${athlete == null ? 'el atleta' : 'el ejercicio'} no se reconoce; no se compara.');
      continue;
    }
    final differences = <String>{};
    for (final month in adj.months) {
      final current = currentReference(
        state.references,
        athleteId: athlete.id,
        exerciseId: rmExerciseId,
        type: ReferenceType.rm,
        on: month,
      );
      if (current?.value != rm.kg) {
        differences.add('${current == null ? 'ninguna' : _fmt(current.value)} el ${aIsoFecha(month)}');
      }
    }
    if (differences.isEmpty) {
      same++;
    } else {
      report.notes.add('$where; la app usa ${differences.join(', ')}.');
    }
  }
  if (same > 0) {
    report.notes.add('KG RM de la grilla: $same de ${grid.rms.length} coinciden con la RM que usa la app cada mes.');
  }
}

String? _resolve(String name, GridAdjustments adj, GridCatalog catalog) {
  final key = plainName(name);
  final alias = adj.exerciseNames[key];
  if (alias != null) return catalog.exerciseIdFor(alias) ?? (catalog.exercises.containsKey(alias) ? alias : null);
  final sheetId = catalog.sheetNames[key];
  final fromSheet = sheetId == null ? null : catalog.exerciseIdFor(sheetId);
  if (fromSheet != null) return fromSheet;
  final byName = catalog.exercises.values.where((e) => plainName(e.name) == key).toList();
  return byName.length == 1 ? byName.single.id : null;
}

String _content(List<WeekModel> models, List<String> assignment) =>
    jsonEncode([for (final m in models) m.toJson(), assignment]);

String _summary(Plan p) {
  var blocks = 0, prescriptions = 0, sets = 0;
  for (final m in p.weekModels) {
    for (final d in m.days) {
      blocks += d.blocks.length;
      for (final b in d.blocks) {
        prescriptions += b.prescriptions.length;
        for (final rx in b.prescriptions) {
          sets += rx.sets.length;
        }
      }
    }
  }
  return '${p.weekModels.length} semanas, ${p.weekModels.isEmpty ? 0 : p.weekModels.first.days.length} días por '
      'semana, $blocks bloques, $prescriptions prescripciones, $sets series';
}

String _fmt(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

class _Built {
  _Built(this.plan, this.dayNumbers, this.problems, this.notes);

  final Plan plan;

  /// The grid's `DIA n` numbers in order: the plan's day `i + 1` is the grid's day `dayNumbers[i]`.
  final List<int> dayNumbers;
  final List<String> problems;
  final List<String> notes;
}

class _PlanBuilder {
  _PlanBuilder(this.grid, this.adj, this.catalog, this.clubId, this.now);

  final PlanningGrid grid;
  final GridAdjustments adj;
  final GridCatalog catalog;
  final String clubId;
  final DateTime now;
  final problems = <String>[];
  final notes = <String>[];
  final _unknown = <String, List<String>>{};

  /// `day|message` → the weeks it happens in, so a remark repeated every week is one line.
  final _dayNotes = <String, List<int>>{};
  void _note(int day, int week, String message) => _dayNotes.putIfAbsent('$day|$message', () => []).add(week);

  _Built build() {
    final dayNumbers = grid.days.keys.toList()..sort();
    final models = [
      for (final w in grid.weeks)
        WeekModel(
          id: 's$w',
          name: 'Semana $w',
          days: [
            for (final d in dayNumbers)
              PlanDay(
                blocks: [for (final b in grid.days[d]![w]!) ..._blocks(b, d, w)],
              ),
          ],
        ),
    ];
    for (final MapEntry(key: key, value: weeks) in _dayNotes.entries) {
      final i = key.indexOf('|');
      notes.add('Día ${key.substring(0, i)} (semana${weeks.length > 1 ? 's' : ''} ${weeks.join(', ')}): ${key.substring(i + 1)}.');
    }
    for (final e in _unknown.entries) {
      problems.add('El ejercicio "${e.key}" no está en el catálogo; no entra (${e.value.join('; ')}).');
    }
    final plan = Plan(
      id: importedId(clubId, adj.planKey),
      clubId: clubId,
      name: adj.planName,
      type: PlanType.history,
      weekModels: models,
      weekAssignment: [for (final w in grid.weeks) 's$w'],
      auditoria: Auditoria.nueva(importAuthor, ahora: now),
    );
    return _Built(plan, dayNumbers, problems, notes);
  }

  List<PlanBlock> _blocks(GridBlock block, int day, int week) {
    final where = 'semana $week, día $day';
    final note = block.notes.isEmpty ? null : block.notes.join(' · ');
    final items = <(Prescription, Exercise)>[];
    if (block.kind == GridBlockKind.wod) {
      for (final line in block.notes) {
        final id = _resolve(line, adj, catalog);
        if (id != null && catalog.exercises[id] != null) items.add((Prescription(exerciseId: id), catalog.exercises[id]!));
      }
      if (items.isEmpty) {
        if (note != null) _note(day, week, 'el WOD ("$note") no nombra ningún ejercicio del catálogo; no entra');
        return const [];
      }
      return [
        PlanBlock(name: block.name, categoryId: wodCategoryId, note: note, prescriptions: [for (final i in items) i.$1]),
      ];
    }
    for (final entry in block.entries) {
      final id = _resolve(entry.exercise, adj, catalog);
      final exercise = id == null ? null : catalog.exercises[id];
      if (exercise == null) {
        _unknown.putIfAbsent(entry.exercise, () => []).add('$where, fila ${entry.row}');
        continue;
      }
      items.add((_prescription(entry, exercise, where, day, week), exercise));
    }
    if (items.isEmpty) {
      if (note != null || block.entries.isNotEmpty) {
        _note(day, week, '"${block.name}" no tiene ejercicios del catálogo${note == null ? '' : ' ($note)'}; no entra');
      }
      return const [];
    }
    final preferred = block.kind == GridBlockKind.warmUp ? ['calentamiento', ..._categoryOrder] : _categoryOrder;
    final shared = preferred.where((c) => items.every((i) => i.$2.categoryIds.contains(c))).firstOrNull;
    if (shared != null) {
      return [PlanBlock(name: block.name, categoryId: shared, note: note, prescriptions: [for (final i in items) i.$1])];
    }
    // No category fits them all: one block per run of the same category.
    String own(Exercise e) =>
        preferred.where(e.categoryIds.contains).firstOrNull ?? e.categoryIds.firstOrNull ?? preferred.first;
    final runs = <(String, List<Prescription>)>[];
    for (final (rx, exercise) in items) {
      final category = own(exercise);
      if (runs.isNotEmpty && runs.last.$1 == category) {
        runs.last.$2.add(rx);
      } else {
        runs.add((category, [rx]));
      }
    }
    _note(
      day,
      week,
      '"${block.name}" mezcla categorías (${runs.map((r) => r.$1).join(', ')}); queda en ${runs.length} bloques',
    );
    return [
      for (var r = 0; r < runs.length; r++)
        PlanBlock(
          name: '${block.name} · ${_categoryNames[runs[r].$1] ?? runs[r].$1}',
          categoryId: runs[r].$1,
          note: r == 0 ? note : null,
          prescriptions: runs[r].$2,
        ),
    ];
  }

  Prescription _prescription(GridEntry entry, Exercise exercise, String where, int day, int week) {
    final sets = parseGridSets(entry.sets);
    if (sets == null && entry.sets.isNotEmpty) {
      problems.add('$where, fila ${entry.row}: las series "${entry.sets}" de "${entry.exercise}" no se entienden.');
    }
    final repeatsName = plainName(entry.load) == plainName(entry.exercise);
    if (repeatsName) {
      _note(day, week, 'la columna de carga de "${entry.exercise}" repite su nombre (fila ${entry.row}); se ignora');
    }
    final load = parseGridLoad(repeatsName ? '' : entry.load);
    final inSeconds = exercise.metrics.contains(Metric.time) && !exercise.metrics.contains(Metric.reps);
    final note = [?load.note, if (sets != null && sets.rest.isNotEmpty) sets.rest].join(' · ');
    return Prescription(
      exerciseId: exercise.id,
      sets: [
        for (final r in sets?.reps ?? const <int>[])
          PlanSet(reps: inSeconds ? null : r, seconds: inSeconds ? r : null, pct: load.pct, kg: load.kg),
      ],
      note: note.isEmpty ? null : note,
      barKg: load.barKg,
    );
  }
}
