import 'dart:convert';

import 'package:maktub_backend/features/import/catalog/catalog_sheets.dart';
import 'package:maktub_backend/features/import/import_report.dart';
import 'package:maktub_backend/features/import/import_run.dart';
import 'package:maktub_backend/features/import/plans/historic_plans.dart';
import 'package:maktub_backend/features/import/plans/plan_sheets.dart';
import 'package:maktub_backend/features/plan/publicar/publicar.dart';
import 'package:maktub_core/maktub_core.dart';

/// The block kinds of the old app's days (`reference/DISENO.md`, "El modelo"), as they appear in the
/// `bloque` column of PlanEjercicios and Registro.
abstract final class SheetBlocks {
  static const stretching = 'estiramiento';
  static const warmUp = 'calentamiento';
  static const main = 'principal';
  static const accessories = 'final';
}

/// The week models of a plan older than PlanModelos: its variants, in the weeks the old app gave them
/// (`reference/DISENO.md`, "El ciclo": 1 and 4 `descarga`, 2 `carga`, 3 `carga2` or else `carga`).
const legacyVariants = ['descarga', 'carga', 'carga2'];
const _legacyNames = {'descarga': 'Descarga', 'carga': 'Carga', 'carga2': 'Carga 2'};

/// What the plan import needs from the catalog: the E8.2 id maps and the catalog as it is (or will be
/// once the catalog step is applied).
class PlanCatalog {
  const PlanCatalog({
    required this.exerciseIdFor,
    required this.timerIdFor,
    required this.exercises,
    required this.sheetExercises,
  });

  /// Sheet exercise id → app id (`CatalogPlan.exerciseIdFor`).
  final String? Function(String sheetId) exerciseIdFor;

  /// Sheet timer id → app id (`CatalogPlan.timerIds`).
  final String? Function(String sheetId) timerIdFor;

  /// App exercises visible to the club, by id.
  final Map<String, Exercise> exercises;

  /// The rows of Ejercicios, for the old app's automatic stretching and warm-up lists.
  final List<SheetExercise> sheetExercises;
}

/// Where a sheet row of an imported plan landed, for the history import (E8.5): Registro names the plan,
/// `modelo`, `dia`, `bloque`, `grupo`, `orden`, `ejercicio` and `serie` of each set.
class PlanLocation {
  const PlanLocation({
    required this.planId,
    required this.weekModelId,
    required this.dayIndex,
    required this.blockIndex,
    required this.prescriptionIndex,
    this.setNumbers = const [],
  });

  final String planId;
  final String weekModelId;
  final int dayIndex;
  final int blockIndex;
  final int prescriptionIndex;

  /// The sheet's `serie` numbers, in the order of the prescription's sets (empty when it has none).
  final List<int> setNumbers;

  /// The 0-based set index of the sheet's [serie], or null if the prescription has no such set.
  int? setIndexOf(int serie) {
    final i = setNumbers.indexOf(serie);
    return i < 0 ? null : i;
  }
}

/// A plan as the sheets describe it, ready to be saved.
class ImportedPlan {
  const ImportedPlan({required this.sheetId, required this.plan, required this.problems, this.history = false});

  final String sheetId;
  final Plan plan;

  /// Published in history mode ([SheetPlan.history]).
  final bool history;

  /// What stops it from being published (`validatePlan`). Empty: it is published.
  final List<PlanProblem> problems;

  bool get publishable => problems.isEmpty;
}

/// What the plan import has to do.
class PlanImportPlan {
  PlanImportPlan._() : report = ImportReport('Planes');

  final ImportReport report;

  /// New plans: created, saved and, when [ImportedPlan.publishable], published.
  final toCreate = <ImportedPlan>[];

  /// Drafts the importer itself saved, never published nor edited in the app, that the sheet and adjustments now
  /// describe differently (a `plans.pctFills` value supplied later): saved again and published if complete.
  final toUpdate = <ImportedPlan>[];

  /// Plans already saved exactly like the sheet but never published (a run cut between saving and
  /// publishing): published now.
  final toPublish = <String>[];

  /// The plans built from Registro, published in history mode.
  final historyPlanIds = <String>{};

  /// The plans built from the `historico` rows of Registro ([historicPlans]): where each row went and who
  /// recorded in each plan. Filled by [PlanImport.plan].
  HistoricPlans historic = HistoricPlans();
  final _exact = <String, PlanLocation>{};
  final _byExercise = <String, PlanLocation>{};
  final _planIds = <String, String>{};

  /// Sheet plan id → the PlanEjercicios rows of exercises measured by % of RM that have no %: what keeps the
  /// plan a draft until `plans.pctFills` supplies them.
  final missingPct = <String, List<SheetSetRow>>{};
  final _dayIndexes = <String, int>{};

  bool get isEmpty => toCreate.isEmpty && toUpdate.isEmpty && toPublish.isEmpty;

  /// The catalog step has work left: its exercises are not there yet, so nothing may be written.
  bool catalogPending = false;

  /// The app id of the sheet plan [sheetPlanId], or null if Planes has no such plan.
  String? planIdOf(String sheetPlanId) => _planIds[sheetPlanId];

  /// The 0-based index of the PlanDias day number [day] of [sheetPlanId], or null if the plan has no such day.
  int? dayIndexOf(String sheetPlanId, int day) => _dayIndexes['$sheetPlanId|$day'];

  /// Where the Registro row with these columns lands in the imported plan, or null. Stretching and the
  /// warm-up lists of PlanDias have no group or order, so a row that does not match exactly is looked
  /// up by exercise in its block.
  PlanLocation? locate({
    required String sheetPlanId,
    required String variant,
    required int day,
    required String block,
    String group = '',
    int order = 0,
    required String exercise,
  }) {
    final b = block.toLowerCase();
    final v = variant.toLowerCase();
    return _exact[_key(sheetPlanId, v, day, b, _groupKey(b, group), order, exercise)] ??
        _byExercise[_key(sheetPlanId, v, day, b, '', 0, exercise)];
  }
}

String _key(String plan, String variant, int day, String block, String group, int order, String exercise) =>
    '$plan|$variant|$day|$block|$group|$order|$exercise';

/// Accessories without a group are one group, like the old app (`agruparFinal`).
String _groupKey(String block, String group) => block == SheetBlocks.accessories && group.isEmpty ? '1' : group;

/// Builds each plan of [sheets] and compares it with [existing] (the club's plans by id). Pure, no I/O.
///
/// - **Week models.** PlanModelos and `secuencia` map one to one (an archived model is kept only if the
///   sequence uses it). A plan without `secuencia` has the legacy variants as week models ([legacyVariants]).
///   The model ids stay the sheet's, so Registro's `modelo` names them.
/// - **Days and blocks.** Each day of PlanDias, in every week model, with the blocks of the old app's day in
///   its order (D16: each block has the category its exercises belong to):
///   1. *Estiramiento*: rows of that block, else the PlanDias list, else the old app's automatic list (the
///      sheet's stretches of the primary lift's reference, or with no reference). No sets.
///   2. *Calentamiento*: rows of that block, else the same lists as stretching.
///   3. *Primario* and *Secundario*: the `principal` rows. The primary is the PlanDias one; the others go to
///      the secondary block, or to the primary block when the exercise is primary only.
///   4. One accessory block per `grupo` of `final`, in circuit when it has more than one exercise (a
///      biserie, E7.18).
/// - **Sets.** One per row, ordered by `serie`: `reps` (seconds for an exercise measured only in time) and
///   `pct`. `rpe` goes to the prescription note, `temporizador` to its timer. No sheet carries a bar.
/// - **Existing plans** are never overwritten: equal is "sin cambios", anything else "difiere". The one exception
///   is a draft only the importer ever saved (see [PlanImportPlan.toUpdate]).
PlanImportPlan planPlanImport(
  PlanSheets sheets,
  PlanCatalog catalog, {
  required String clubId,
  required Map<String, Plan> existing,
  required DateTime now,
  List<PctCorrection> corrections = const [],
  List<PctFill> fills = const [],
}) {
  final out = PlanImportPlan._();
  final report = out.report;
  report.problems.addAll(sheets.problems);
  report.notes.addAll(sheets.notes);

  for (final sheetPlan in sheets.plans) {
    final changed = applyPctCorrections(sheetPlan, corrections);
    for (final c in corrections.where((c) => c.planId == sheetPlan.id)) {
      report.notes.add(
        'plan "${sheetPlan.name}" (${sheetPlan.id}): corrección ${_fmt(c.from)} % → ${_fmt(c.to)} % (M1-D4), '
        '$changed series cambiadas (las de trabajo y su rampa).',
      );
    }
    final filled = applyPctFills(sheetPlan, fills);
    report.problems.addAll([for (final p in filled.problems) 'plan "${sheetPlan.name}" (${sheetPlan.id}): $p']);
    if (filled.filled > 0 || filled.pending > 0) {
      report.notes.add(
        'plan "${sheetPlan.name}" (${sheetPlan.id}): plans.pctFills completa ${filled.filled} %'
        '${filled.pending > 0 ? '; ${filled.pending} siguen sin valor' : ''}.',
      );
    }
    out._planIds[sheetPlan.id] = importedId(clubId, sheetPlan.id);
    for (var i = 0; i < sheetPlan.days.length; i++) {
      out._dayIndexes.putIfAbsent('${sheetPlan.id}|${sheetPlan.days[i].day}', () => i);
    }
    final built = _PlanBuilder(sheetPlan, catalog, clubId, now, out).build();
    report.problems.addAll(built.problems);
    report.notes.addAll(built.notes);
    final plan = built.plan;
    final label = 'plan "${plan.name}" (${sheetPlan.id})';
    if (!sheetPlan.history) {
      report.notes.add(
        '$label: activo=${sheetPlan.active ? 'sí' : 'no'}, inicio=${sheetPlan.start ?? '-'}: no se importan; '
        'la asignación sale de plans.assignments (paso asignaciones).',
      );
    }

    final missing = out.missingPct[sheetPlan.id] ?? const [];
    if (missing.isNotEmpty) {
      String weeks(String variant) {
        final n = [
          for (var w = 0; w < plan.weekAssignment.length; w++)
            if (plan.weekAssignment[w] == variant) w + 1,
        ];
        return n.isEmpty ? 'ninguna semana' : 'semana${n.length > 1 ? 's' : ''} ${n.join(', ')}';
      }

      report.notes.add(
        '$label: faltan ${missing.length} % de ejercicios medidos por % de RM; se completan en plans.pctFills: '
        '${[for (final r in missing) '${r.variant} (${weeks(r.variant)}), día ${r.day}, ${r.block}, "${r.exercise}", '
              'serie ${r.set} (reps ${r.reps ?? '-'}${r.rpe == null ? '' : ', rpe ${r.rpe}'})'].join('; ')}.',
      );
    }
    final all = validatePlan(plan, exerciseById: (id) => catalog.exercises[id]);
    final problems = sheetPlan.history
        ? [
            for (final p in all)
              if (!historyPublishAccepts.contains(p.code)) p,
          ]
        : all;
    if (sheetPlan.history) {
      out.historyPlanIds.add(plan.id);
      final accepted = all.length - problems.length;
      if (accepted > 0) {
        report.notes.add(
          '$label: plan armado con lo que registró Registro; $accepted series sin % o sin reps (la planilla '
          'nunca los tuvo) se aceptan al publicar en modo historial.',
        );
      }
    }
    final imported = ImportedPlan(sheetId: sheetPlan.id, plan: plan, problems: problems, history: sheetPlan.history);
    if (problems.isNotEmpty) {
      report.notes.add(
        '$label queda en borrador: no se puede publicar (${problems.length} problemas): '
        '${_describe(plan, problems, catalog).join('; ')}.',
      );
    }

    final stored = existing[plan.id];
    if (stored == null) {
      out.toCreate.add(imported);
      report.created.add('$label: ${_summary(plan)}; ${problems.isEmpty ? 'se publica' : 'queda en borrador'}.');
    } else if (_content(stored) != _content(plan) && _ownDraft(stored)) {
      out.toUpdate.add(imported);
      report.updated.add(
        '$label: borrador del importador que la planilla y los ajustes ahora completan de otra forma '
        '(${_whatDiffers(stored, plan)}); se guarda de nuevo y ${problems.isEmpty ? 'se publica' : 'sigue en borrador'}.',
      );
    } else if (_content(stored) != _content(plan)) {
      report.differing.add('$label: ya existe y no coincide con la planilla (${_whatDiffers(stored, plan)}).');
    } else if (stored.published == null && problems.isEmpty) {
      out.toPublish.add(plan.id);
      report.updated.add('$label: guardado igual a la planilla pero sin publicar; se publica.');
    } else {
      report.unchanged.add(label);
    }
  }
  return out;
}

/// Saved only by the importer and never published: nobody touched it in the app, so it may be saved again.
bool _ownDraft(Plan p) =>
    p.published == null &&
    p.auditoria.creadoPor == importAuthor &&
    (p.auditoria.modificadoPor == null || p.auditoria.modificadoPor == importAuthor);

String _content(Plan p) => jsonEncode([
  p.name.trim(),
  p.type.cable,
  [for (final m in p.weekModels) m.toJson()],
  p.weekAssignment,
]);

String _whatDiffers(Plan stored, Plan plan) {
  if (stored.name.trim() != plan.name.trim()) return 'nombre';
  if (stored.type != plan.type) return 'tipo';
  if (jsonEncode(stored.weekAssignment) != jsonEncode(plan.weekAssignment)) return 'secuencia de semanas';
  final ids = {for (final m in plan.weekModels) m.id: m};
  final storedIds = {for (final m in stored.weekModels) m.id: m};
  if (!ids.keys.toSet().containsAll(storedIds.keys) || !storedIds.keys.toSet().containsAll(ids.keys)) {
    return 'modelos de semana';
  }
  final differing = [
    for (final id in ids.keys)
      if (jsonEncode(ids[id]!.toJson()) != jsonEncode(storedIds[id]!.toJson())) ids[id]!.name,
  ];
  return 'contenido de ${differing.join(', ')}';
}

String _summary(Plan p) {
  final days = p.weekModels.isEmpty ? 0 : p.weekModels.first.days.length;
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
  return '${p.weekModels.length} modelos (${p.weekModels.map((m) => m.name).join(', ')}), '
      'secuencia ${p.weekAssignment.join('-')}, $days días por semana, $blocks bloques, '
      '$prescriptions prescripciones, $sets series';
}

/// The publish problems in words, one per prescription (not per set).
List<String> _describe(Plan plan, List<PlanProblem> problems, PlanCatalog catalog) {
  final lines = <String>{};
  for (final p in problems) {
    final where = <String>[];
    final m = p.weekModelIndex;
    if (m != null) {
      final model = plan.weekModels[m];
      where.add(model.name);
      final d = p.dayIndex;
      if (d != null) {
        where.add('día ${d + 1}');
        final b = p.blockIndex;
        if (b != null) {
          final block = model.days[d].blocks[b];
          where.add(block.name);
          final rx = p.prescriptionIndex;
          if (rx != null) {
            final id = block.prescriptions[rx].exerciseId;
            where.add(catalog.exercises[id]?.name ?? id ?? '?');
          }
        }
      }
    }
    lines.add('${p.code.name}${where.isEmpty ? '' : ' (${where.join(', ')})'}');
  }
  return lines.toList();
}

String _fmt(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

class _Built {
  _Built(this.plan, this.problems, this.notes);

  final Plan plan;
  final List<String> problems;
  final List<String> notes;
}

/// One exercise of one block with its rows, as the old app grouped them (`itemsDeBloque`).
class _Item {
  _Item(this.group, this.order, this.exercise);

  final String group;
  final int order;
  final String exercise;
  final rows = <SheetSetRow>[];
}

class _PlanBuilder {
  _PlanBuilder(this.sheet, this.catalog, this.clubId, this.now, this.out);

  final SheetPlan sheet;
  final PlanCatalog catalog;
  final String clubId;
  final DateTime now;
  final PlanImportPlan out;
  final problems = <String>{};
  final notes = <String>{};

  String get planId => importedId(clubId, sheet.id);
  String get label => 'plan "${sheet.name}" (${sheet.id})';

  _Built build() {
    final (models, assignment) = _weekModels();
    final modelIds = {for (final m in models) m.id};
    final dayNumbers = {for (final d in sheet.days) d.day};
    final skipped = <String, List<int>>{};
    for (final r in sheet.rows) {
      if (!modelIds.contains(r.variant)) {
        skipped.putIfAbsent('la variante "${r.variant}" no es un modelo de semana del plan', () => []).add(r.line);
      } else if (!dayNumbers.contains(r.day)) {
        skipped.putIfAbsent('el día ${r.day} no está en PlanDias', () => []).add(r.line);
      } else if (!const {
        SheetBlocks.stretching,
        SheetBlocks.warmUp,
        SheetBlocks.main,
        SheetBlocks.accessories,
      }.contains(r.block)) {
        skipped.putIfAbsent('bloque "${r.block}" desconocido', () => []).add(r.line);
      }
    }
    for (final e in skipped.entries) {
      problems.add(
        '$label: ${e.value.length} filas de PlanEjercicios no se importan: ${e.key} (líneas ${_lines(e.value)}).',
      );
    }

    final weekModels = [
      for (final m in models)
        WeekModel(
          id: m.id,
          name: m.name,
          days: _trimmed([for (var i = 0; i < sheet.days.length; i++) _day(m.id, i, sheet.days[i])]),
        ),
    ];
    final plan = Plan(
      id: planId,
      clubId: clubId,
      name: sheet.name.trim(),
      weekModels: weekModels,
      weekAssignment: assignment,
      auditoria: Auditoria.nueva(importAuthor, ahora: now),
    );
    return _Built(plan, problems.toList(), notes.toList());
  }

  (List<SheetWeekModel>, List<String>) _weekModels() {
    if (sheet.sequence.isNotEmpty) {
      final models = <SheetWeekModel>[];
      for (final m in sheet.weekModels) {
        if (m.archived && !sheet.sequence.contains(m.id)) {
          notes.add('$label: el modelo "${m.name}" (${m.id}) está archivado y la secuencia no lo usa; no se importa.');
        } else {
          models.add(m);
        }
      }
      final unknown = sheet.sequence.where((id) => !models.any((m) => m.id == id)).toSet();
      if (unknown.isNotEmpty) {
        problems.add('$label: la secuencia usa modelos que no están en PlanModelos: ${unknown.join(', ')}.');
      }
      return (models, sheet.sequence);
    }
    if (sheet.weekModels.isNotEmpty) {
      notes.add('$label: tiene PlanModelos pero no secuencia; se usan las variantes viejas.');
    }
    final variants = {for (final r in sheet.rows) r.variant};
    final present = [
      for (final v in legacyVariants)
        if (variants.contains(v) || v != 'carga2') v,
    ];
    final week3 = variants.contains('carga2') ? 'carga2' : 'carga';
    return (
      [for (final v in present) SheetWeekModel(id: v, name: _legacyNames[v]!, archived: false)],
      ['descarga', 'carga', week3, 'descarga'],
    );
  }

  /// A history plan's week keeps only the days it has: its trailing days without blocks are dropped.
  List<PlanDay> _trimmed(List<PlanDay> days) {
    if (!sheet.history) return days;
    var n = days.length;
    while (n > 0 && days[n - 1].blocks.isEmpty) {
      n--;
    }
    return days.sublist(0, n);
  }

  PlanDay _day(String variant, int dayIndex, SheetDay day) {
    final dayRows = sheet.rows.where((r) => r.day == day.day).toList();
    final rows = dayRows.where((r) => r.variant == variant).toList();
    final blocks = <PlanBlock>[];

    void add(PlanBlock block, List<_Item> items, String sheetBlock) {
      if (block.prescriptions.isEmpty) return;
      final b = blocks.length;
      blocks.add(block);
      for (var p = 0; p < items.length; p++) {
        final item = items[p];
        final location = PlanLocation(
          planId: planId,
          weekModelId: variant,
          dayIndex: dayIndex,
          blockIndex: b,
          prescriptionIndex: p,
          setNumbers: [for (final r in item.rows) r.set],
        );
        out._exact[_key(sheet.id, variant, day.day, sheetBlock, item.group, item.order, item.exercise)] = location;
        out._byExercise.putIfAbsent(_key(sheet.id, variant, day.day, sheetBlock, '', 0, item.exercise), () => location);
      }
    }

    // 1-2. Stretching and warm-up: their rows if the day has any (in any variant), else the lists.
    for (final (kind, name, list) in [
      (SheetBlocks.stretching, 'Estiramiento', day.stretching),
      (SheetBlocks.warmUp, 'Calentamiento', day.warmUp),
    ]) {
      final items = dayRows.any((r) => r.block == kind)
          ? _items(rows.where((r) => r.block == kind))
          : sheet.history
          ? <_Item>[]
          : [for (final id in _list(kind, list, day)) _Item('', 0, id)];
      final resolved = _resolved(items);
      add(PlanBlock(name: name, categoryId: kind, prescriptions: _prescriptions(resolved)), resolved, kind);
    }

    // 3. Primary and secondary, from `principal`. The primary is chosen over every variant of the day, so
    // it is the same exercise in all week models.
    final mainItems = _items(dayRows.where((r) => r.block == SheetBlocks.main));
    if (mainItems.isNotEmpty) {
      final primary =
          mainItems.where((i) => i.exercise == day.primary).firstOrNull ??
          mainItems.where((i) => _sheetCategories(i.exercise).contains('primario')).firstOrNull ??
          mainItems.first;
      final ofVariant = _resolved(_items(rows.where((r) => r.block == SheetBlocks.main)));
      bool same(_Item a, _Item b) => a.group == b.group && a.order == b.order && a.exercise == b.exercise;
      final first = [
        ...ofVariant.where((i) => same(i, primary)),
        ...ofVariant.where((i) => !same(i, primary) && _mainCategory(i) == 'primario'),
      ];
      final second = [
        for (final i in ofVariant)
          if (!first.contains(i)) i,
      ];
      add(
        PlanBlock(name: 'Primario', categoryId: 'primario', prescriptions: _prescriptions(first)),
        first,
        SheetBlocks.main,
      );
      add(
        PlanBlock(name: 'Secundario', categoryId: 'secundario', prescriptions: _prescriptions(second)),
        second,
        SheetBlocks.main,
      );
    }

    // 4. Accessories: one block per group.
    final groups = <String, List<_Item>>{};
    for (final i in _resolved(_items(rows.where((r) => r.block == SheetBlocks.accessories)))) {
      groups.putIfAbsent(i.group, () => []).add(i);
    }
    final names = <String, int>{};
    for (final items in groups.values) {
      final base = switch (items.length) {
        1 => 'Accesorios',
        2 => 'Biserie',
        3 => 'Triserie',
        final n => 'Serie de $n',
      };
      final n = names[base] = (names[base] ?? 0) + 1;
      add(
        PlanBlock(
          name: n == 1 ? base : '$base $n',
          categoryId: 'accesorio',
          executionMode: items.length > 1 ? ExecutionMode.circuit : ExecutionMode.sequential,
          prescriptions: _prescriptions(items),
        ),
        items,
        SheetBlocks.accessories,
      );
    }
    return PlanDay(blocks: blocks);
  }

  /// The exercise ids of a stretching or warm-up list of PlanDias, or the old app's automatic ones
  /// (`listaSinCarga`): the sheet's active exercises of that category whose reference is the primary's,
  /// or that have none.
  List<String> _list(String category, List<String> explicit, SheetDay day) {
    if (explicit.isNotEmpty) return explicit;
    final primary = catalog.sheetExercises.where((e) => e.id == day.primary).firstOrNull;
    return [
      for (final e in catalog.sheetExercises)
        if (!e.inactive &&
            e.categories.contains(category) &&
            (e.reference == null || e.reference == primary?.reference))
          e.id,
    ];
  }

  List<String> _sheetCategories(String sheetId) =>
      catalog.sheetExercises.where((e) => e.id == sheetId).firstOrNull?.categories ??
      catalog.exercises[catalog.exerciseIdFor(sheetId)]?.categoryIds ??
      const [];

  /// A non-primary exercise of `principal` goes to the secondary block, unless the catalog only has it as
  /// a primary (a Zercher squat used as the day's second lift).
  String _mainCategory(_Item i) {
    final categories = catalog.exercises[catalog.exerciseIdFor(i.exercise)]?.categoryIds ?? const [];
    return !categories.contains('secundario') && categories.contains('primario') ? 'primario' : 'secundario';
  }

  List<_Item> _items(Iterable<SheetSetRow> rows) {
    final byKey = <String, _Item>{};
    for (final r in rows) {
      final group = _groupKey(r.block, r.group);
      byKey.putIfAbsent('$group|${r.order}|${r.exercise}', () => _Item(group, r.order, r.exercise)).rows.add(r);
    }
    final items = byKey.values.toList()
      ..sort((a, b) {
        final g = _compareGroups(a.group, b.group);
        return g != 0 ? g : a.order.compareTo(b.order);
      });
    for (final i in items) {
      i.rows.sort((a, b) => a.set.compareTo(b.set));
    }
    return items;
  }

  static int _compareGroups(String a, String b) {
    final x = int.tryParse(a), y = int.tryParse(b);
    return x != null && y != null ? x.compareTo(y) : a.compareTo(b);
  }

  /// [items] without the exercises the catalog does not have (reported).
  List<_Item> _resolved(List<_Item> items) {
    final kept = <_Item>[];
    for (final i in items) {
      if (catalog.exerciseIdFor(i.exercise) != null) {
        kept.add(i);
      } else if (i.rows.isEmpty) {
        notes.add(
          '$label: el ejercicio "${i.exercise}" de PlanDias no está en el catálogo; la app vieja tampoco lo '
          'mostraba. Se omite.',
        );
      } else {
        problems.add(
          '$label: el ejercicio "${i.exercise}" (PlanEjercicios líneas ${_lines([for (final r in i.rows) r.line])}) '
          'no está en el catálogo; no se importa.',
        );
      }
    }
    return kept;
  }

  List<Prescription> _prescriptions(List<_Item> items) => [for (final i in items) _prescription(i)];

  Prescription _prescription(_Item item) {
    final exerciseId = catalog.exerciseIdFor(item.exercise)!;
    final metrics = catalog.exercises[exerciseId]?.metrics ?? const [];
    if (metrics.contains(Metric.loadPctRm) && !sheet.history) {
      out.missingPct.putIfAbsent(sheet.id, () => []).addAll(item.rows.where((r) => r.pct == null));
    }
    final inSeconds = metrics.contains(Metric.time) && !metrics.contains(Metric.reps);
    final rpes = {
      for (final r in item.rows)
        if (r.rpe != null) r.rpe!,
    };
    final timers = {
      for (final r in item.rows)
        if (r.timer != null) r.timer!,
    };
    if (rpes.length > 1 || timers.length > 1) {
      notes.add(
        '$label: "${item.exercise}" (PlanEjercicios líneas ${_lines([for (final r in item.rows) r.line])}) cambia '
        'de rpe o temporizador entre series; vale el de la primera.',
      );
    }
    String? timerId;
    if (timers.isNotEmpty) {
      timerId = catalog.timerIdFor(timers.first);
      if (timerId == null) notes.add('$label: el temporizador "${timers.first}" no está en el catálogo; se omite.');
    }
    return Prescription(
      exerciseId: exerciseId,
      sets: [
        for (final r in item.rows)
          PlanSet(reps: inSeconds ? null : r.reps, seconds: inSeconds ? r.reps : null, pct: r.pct),
      ],
      note: rpes.isEmpty ? null : 'RPE ${rpes.first}',
      timerId: timerId,
    );
  }

  static String _lines(List<int> lines) {
    if (lines.length <= 6) return lines.join(', ');
    return '${lines.take(5).join(', ')}… (${lines.length})';
  }
}
