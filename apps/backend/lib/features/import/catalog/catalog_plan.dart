import 'package:maktub_backend/features/import/adjustments.dart';
import 'package:maktub_backend/features/import/catalog/catalog_sheets.dart';
import 'package:maktub_backend/features/import/import_report.dart';
import 'package:maktub_backend/features/import/import_run.dart';
import 'package:maktub_core/maktub_core.dart';

/// The basic lifts of the old app (`BASICOS`) and the default exercise each one is. The `referencia` of
/// Ejercicios and the `ejercicio` of RMs (E8.3) name them this way.
const basicLiftIds = {'sentadilla': 'sq_espalda', 'peso_muerto': 'dl_convencional', 'bench': 'bp_plano'};

/// The `notas` values that only classified the primary lifts in the old app; they are not notes.
const _classificationNotes = {'basico', 'básico', 'variante'};

/// What the club's catalog has today, the input of [planCatalogImport].
class CatalogState {
  const CatalogState({required this.view, this.timers = const [], this.wods = const []});

  /// Exercises and categories visible to the club (default plus its own, archived included).
  final CatalogView view;

  /// Timers visible to the club.
  final List<Temporizador> timers;

  /// The club's WoD library.
  final List<Wod> wods;
}

/// What the catalog import has to do, and the sheet id → app id maps later steps need.
class CatalogPlan {
  CatalogPlan._(this.clubId, this._baseExerciseIds) : report = ImportReport('Catálogo');

  final String clubId;
  final ImportReport report;
  final Set<String> _baseExerciseIds;

  /// New club exercises, with their final ids.
  final exercisesToCreate = <Exercise>[];

  /// Existing exercises (default or of the club) in their final state, with the sheet categories added.
  final exercisesToUpdate = <Exercise>[];
  final timersToCreate = <Temporizador>[];
  final wodsToCreate = <Wod>[];

  /// Sheet id → app id, for every imported row (created, updated or already there).
  final exerciseIds = <String, String>{};
  final timerIds = <String, String>{};
  final wodIds = <String, String>{};

  bool get isEmpty =>
      exercisesToCreate.isEmpty && exercisesToUpdate.isEmpty && timersToCreate.isEmpty && wodsToCreate.isEmpty;

  /// The app exercise a sheet id names anywhere in the spreadsheet (plans, RMs, history): a row of
  /// Ejercicios, a default exercise with that id (the sheet's Ejercicios lacks some it uses), or a
  /// basic lift key. Null if none.
  String? exerciseIdFor(String sheetId) =>
      exerciseIds[sheetId] ??
      (_baseExerciseIds.contains(sheetId) ? sheetId : null) ??
      (basicLiftIds[sheetId] != null ? exerciseIds[basicLiftIds[sheetId]] ?? basicLiftIds[sheetId] : null);
}

/// Compares the catalog sheets with [state] and decides, row by row (pure, no I/O):
///
/// - **Exercises.** A row matches, in this order: the exercise its id is declared the same as
///   (`sameAs`); the default exercise with its id (unless listed in `notBase`); the club exercise a
///   previous import created ([importedId]); any visible exercise with the same name. A matched row only
///   adds the categories it is missing (tracker, "Para E8.2"); nothing else is overwritten. Otherwise a
///   club exercise is created with the measure, reference and status of the row.
/// - **Timers.** Same order without the adjustments; a missing one is created in the club.
/// - **WoDs.** Into the club's library (E5.10): matched by [importedId] or name, else created, with
///   the timer resolved through the timers above.
CatalogPlan planCatalogImport(
  CatalogSheets sheets,
  CatalogState state, {
  required String clubId,
  ExerciseAdjustments adjustments = const ExerciseAdjustments(),
  required DateTime now,
}) {
  final plan = CatalogPlan._(clubId, {
    for (final e in state.view.exercises.values)
      if (e.clubId == clubPlataforma) e.id,
  });
  plan.report.problems.addAll(sheets.problems);
  plan.report.notes.addAll(sheets.notes);
  final audit = Auditoria.nueva(importAuthor, ahora: now);
  _planExercises(plan, sheets.exercises, state.view, adjustments, audit);
  _planTimers(plan, sheets.timers, state.timers, audit);
  _planWods(plan, sheets.wods, state, audit);
  return plan;
}

void _planExercises(
  CatalogPlan plan,
  List<SheetExercise> rows,
  CatalogView view,
  ExerciseAdjustments adjustments,
  Auditoria audit,
) {
  final clubId = plan.clubId;
  // The catalog as it will be: what each decision sees, so two rows never create the same exercise.
  final exercises = {
    for (final e in view.exercises.values)
      if (isVisibleTo(e, clubId)) e.id: e,
  };
  final created = <String>{};
  final updated = <String, Exercise>{};
  final sources = <String, List<String>>{};
  final report = plan.report;

  for (final row in rows) {
    final label = 'ejercicio "${row.name}" (${row.id})';
    final unknown = [
      for (final c in row.categories)
        if (!_visible(view.categories[c], clubId)) c,
    ];
    if (unknown.isNotEmpty) {
      report.problems.add('$label: categoría desconocida ${unknown.join(', ')}.');
      continue;
    }

    final (existing, how) = _matchExercise(row, exercises, clubId, adjustments, report);
    if (existing == null) {
      final exercise = _exerciseFromRow(row, importedId(clubId, row.id), clubId, audit, report);
      final problems = validateExercise(exercise, _withExercises(view, exercises.values));
      if (problems.isNotEmpty) {
        report.problems.add('$label: ${problems.map((p) => p.name).join(', ')}.');
        continue;
      }
      exercises[exercise.id] = exercise;
      created.add(exercise.id);
      plan.exerciseIds[row.id] = exercise.id;
      continue;
    }

    plan.exerciseIds[row.id] = existing.id;
    final missing = [
      for (final c in row.categories)
        if (!existing.categoryIds.contains(c)) c,
    ];
    final target = missing.isEmpty ? existing : existing.copyWith(categoryIds: [...existing.categoryIds, ...missing]);
    if (missing.isNotEmpty) {
      exercises[existing.id] = target;
      if (created.contains(existing.id)) {
        report.notes.add(
          '$label coincide $how con "${existing.name}", que crea otra fila: se crea con las dos categorías.',
        );
      } else {
        updated[existing.id] = target;
        (sources[existing.id] ??= []).add('fila "${row.name}" (${row.id}) $how');
      }
    } else if (created.contains(existing.id)) {
      report.notes.add('$label coincide $how con "${existing.name}", que crea otra fila de esta misma planilla.');
    } else {
      report.unchanged.add('$label → "${existing.name}" (${existing.id}), $how');
    }

    final isDefault = existing.clubId == clubPlataforma;
    if (isDefault && normalizeName(existing.name) != normalizeName(row.name)) {
      report.notes.add('$label es el default "${existing.name}" con otro nombre; queda el nombre del default.');
    }
    if (isDefault && row.inactive && existing.isActive) {
      report.differing.add('$label: inactivo en la planilla, pero un default no se archiva por un club.');
    }
    if (!isDefault && !created.contains(existing.id)) {
      final fromRow = _exerciseFromRow(row, existing.id, clubId, existing.auditoria, null);
      final diffs = _exerciseDiffs(existing, fromRow);
      if (diffs.isNotEmpty) report.differing.add('$label: ${diffs.join(', ')} distinto en la app.');
    }
  }

  for (final id in created) {
    final e = exercises[id]!;
    plan.exercisesToCreate.add(e);
    report.created.add(
      'ejercicio "${e.name}" ($id): ${e.categoryIds.join(', ')}, ${_describeLoad(e)}'
      '${e.isActive ? '' : ', archivado'}',
    );
  }
  for (final e in updated.values) {
    plan.exercisesToUpdate.add(e);
    final before = view.exercises[e.id]!;
    report.updated.add(
      'ejercicio "${e.name}" (${e.id}${e.clubId == clubPlataforma ? ', default' : ''}): '
      '+ categoría ${e.categoryIds.where((c) => !before.categoryIds.contains(c)).join(', ')}, '
      'por ${sources[e.id]!.join(' y ')}',
    );
  }
}

(Exercise?, String) _matchExercise(
  SheetExercise row,
  Map<String, Exercise> exercises,
  String clubId,
  ExerciseAdjustments adjustments,
  ImportReport report,
) {
  final same = adjustments.sameAs[row.id];
  if (same != null) {
    final target = exercises[same];
    if (target != null) return (target, 'por ajuste (sameAs)');
    report.notes.add('Ajuste sameAs ${row.id} → $same: "$same" no existe; se sigue con las demás reglas.');
  }
  if (!adjustments.notBase.contains(row.id)) {
    final base = exercises[row.id];
    if (base != null && base.clubId == clubPlataforma) return (base, 'por id');
  }
  final own = exercises[importedId(clubId, row.id)];
  if (own != null && own.clubId == clubId) return (own, 'por id importado');
  final name = normalizeName(row.name);
  for (final e in exercises.values) {
    if (normalizeName(e.name) == name) return (e, 'por nombre');
  }
  return (null, '');
}

/// The club exercise a row describes (`reference/Plan.html`, `porcentual`): a weighed exercise with a
/// basic reference outside warm-up and stretching loads as a % of that lift's RM; a weighed one without
/// it, with the athlete's fixed weight. In warm-ups and stretches the reference only says which lift they
/// go with, so it becomes a suggestion, like in the base list.
Exercise _exerciseFromRow(SheetExercise row, String id, String clubId, Auditoria audit, ImportReport? report) {
  final basic = row.reference == null ? null : basicLiftIds[row.reference];
  if (row.reference != null && basic == null) {
    report?.notes.add('ejercicio "${row.name}" (${row.id}): referencia "${row.reference}" desconocida; se ignora.');
  }
  final loadsByPercent =
      row.measure == SheetMeasure.weight &&
      basic != null &&
      row.categories.any((c) => c != 'calentamiento' && c != 'estiramiento');
  final (metrics, target) = switch (row.measure) {
    SheetMeasure.weight when loadsByPercent => ([Metric.loadPctRm, Metric.reps], Metric.loadPctRm),
    SheetMeasure.weight => ([Metric.fixedLoad, Metric.reps], Metric.fixedLoad),
    SheetMeasure.reps => ([Metric.reps], Metric.reps),
    SheetMeasure.time => ([Metric.time], Metric.time),
  };
  final notes = row.notes;
  return Exercise(
    id: id,
    clubId: clubId,
    name: row.name,
    categoryIds: row.categories,
    metrics: metrics,
    defaultMetric: target,
    loadReference: loadsByPercent ? LoadReference.otherExercise(basic) : const LoadReference.none(),
    suggestionIds: basic != null && !loadsByPercent ? [basic] : const [],
    notes: notes == null || _classificationNotes.contains(notes.toLowerCase()) ? null : notes,
    status: row.inactive ? CatalogStatus.archived : CatalogStatus.active,
    auditoria: audit,
  );
}

List<String> _exerciseDiffs(Exercise app, Exercise sheet) => [
  if (normalizeName(app.name) != normalizeName(sheet.name)) 'nombre',
  if (!_sameList(app.metrics, sheet.metrics) || app.defaultMetric != sheet.defaultMetric) 'medida',
  if (app.loadReference != sheet.loadReference) 'referencia',
  if (!_sameList(app.suggestionIds, sheet.suggestionIds)) 'sugerencias',
  if (app.notes != sheet.notes) 'notas',
  if (app.status != sheet.status) 'estado',
];

String _describeLoad(Exercise e) => switch (e.loadReference.kind) {
  LoadReferenceKind.otherExercise => '% del RM de ${e.loadReference.exerciseId}',
  _ when e.metrics.contains(Metric.fixedLoad) => 'kilaje fijo',
  _ when e.metrics.contains(Metric.time) => 'por tiempo',
  _ => 'por repeticiones',
};

void _planTimers(CatalogPlan plan, List<SheetTimer> rows, List<Temporizador> visible, Auditoria audit) {
  final clubId = plan.clubId;
  final timers = {
    for (final t in visible)
      if (isVisibleTo(t, clubId)) t.id: t,
  };
  final report = plan.report;
  for (final row in rows) {
    final label = 'temporizador "${row.body['nombre']}" (${row.id})';
    final Temporizador fromRow;
    try {
      fromRow = Temporizador.fromJson({
        ...row.body,
        'id': importedId(clubId, row.id),
        'clubId': clubId,
        'estado': CatalogStatus.active.cable,
      }).copyWith(auditoria: audit);
    } on Object {
      report.problems.add('$label: tipo "${row.body['tipo']}" desconocido.');
      continue;
    }
    final base = timers[row.id];
    final own = timers[importedId(clubId, row.id)];
    final name = normalizeName(fromRow.nombre);
    final existing =
        (base != null && base.clubId == clubPlataforma ? base : null) ??
        (own != null && own.clubId == clubId ? own : null) ??
        timers.values.where((t) => normalizeName(t.nombre) == name).firstOrNull;
    if (existing != null) {
      plan.timerIds[row.id] = existing.id;
      final diffs = [
        if (normalizeName(existing.nombre) != name) 'nombre',
        if (existing.tipo != fromRow.tipo) 'tipo',
        if (existing.trabajoSeg != fromRow.trabajoSeg) 'trabajo',
        if (existing.descansoSeg != fromRow.descansoSeg) 'descanso',
        if (existing.rondas != fromRow.rondas) 'rondas',
      ];
      if (diffs.isEmpty) {
        report.unchanged.add('$label → ${existing.id}');
      } else {
        report.differing.add('$label: ${diffs.join(', ')} distinto en "${existing.nombre}" (${existing.id}).');
      }
      continue;
    }
    final problems = fromRow.validar();
    if (problems.isNotEmpty) {
      report.problems.add('$label: ${problems.map((p) => p.name).join(', ')}.');
      continue;
    }
    timers[fromRow.id] = fromRow;
    plan.timerIds[row.id] = fromRow.id;
    plan.timersToCreate.add(fromRow);
    report.created.add('$label: ${fromRow.tipo.cable}');
  }
}

void _planWods(CatalogPlan plan, List<SheetWod> rows, CatalogState state, Auditoria audit) {
  final clubId = plan.clubId;
  final report = plan.report;
  final wods = {
    for (final w in state.wods)
      if (w.clubId == clubId) w.id: w,
  };
  final visibleTimers = {
    for (final t in [...state.timers, ...plan.timersToCreate])
      if (isVisibleTo(t, clubId)) t.id: t,
  };
  for (final row in rows) {
    final label = 'WoD "${row.name}" (${row.id})';
    String? timerId;
    if (row.timerId != null) {
      timerId = plan.timerIds[row.timerId] ?? (visibleTimers.containsKey(row.timerId) ? row.timerId : null);
      if (timerId == null) {
        report.notes.add('$label: el temporizador "${row.timerId}" no existe; queda sin temporizador.');
      }
    } else if (row.format == 'for_time') {
      // The library has no format field: a for time without timer gets the stopwatch, which is what the
      // app uses for "for time" without a cap.
      final stopwatch =
          visibleTimers.values
              .where(
                (t) => t.tipo == TipoTemporizador.forTime && t.limiteSeg == null && t.estado == CatalogStatus.active,
              )
              .toList()
            ..sort((a, b) => (a.clubId == clubPlataforma ? 0 : 1).compareTo(b.clubId == clubPlataforma ? 0 : 1));
      if (stopwatch.isNotEmpty) {
        timerId = stopwatch.first.id;
        report.notes.add('$label: for time sin temporizador en la planilla; se le asigna "${stopwatch.first.nombre}".');
      }
    }
    final fromRow = Wod(
      id: importedId(clubId, row.id),
      clubId: clubId,
      name: row.name,
      description: row.description,
      timerId: timerId,
      auditoria: audit,
    );
    final name = normalizeName(row.name);
    final existing = wods[fromRow.id] ?? wods.values.where((w) => normalizeName(w.name) == name).firstOrNull;
    if (existing != null) {
      plan.wodIds[row.id] = existing.id;
      final diffs = [
        if (normalizeName(existing.name) != name) 'nombre',
        if (existing.description != fromRow.description) 'descripción',
        if (existing.timerId != fromRow.timerId) 'temporizador',
      ];
      if (diffs.isEmpty) {
        report.unchanged.add('$label → ${existing.id}');
      } else {
        report.differing.add('$label: ${diffs.join(', ')} distinto en la biblioteca.');
      }
      continue;
    }
    final problems = validateWod(fromRow);
    if (problems.isNotEmpty) {
      report.problems.add('$label: ${problems.map((p) => p.code.name).join(', ')}.');
      continue;
    }
    wods[fromRow.id] = fromRow;
    plan.wodIds[row.id] = fromRow.id;
    plan.wodsToCreate.add(fromRow);
    report.created.add('$label en la biblioteca de WoDs${timerId == null ? '' : ', temporizador $timerId'}');
  }
}

bool _visible(DelClub? item, String clubId) => item != null && isVisibleTo(item, clubId);

CatalogView _withExercises(CatalogView view, Iterable<Exercise> exercises) => CatalogView.of(
  exercises: exercises,
  categories: view.categories.values,
  groups: view.groups.values,
  patterns: view.patterns.values,
);

bool _sameList<T>(List<T> a, List<T> b) =>
    a.length == b.length && [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);
