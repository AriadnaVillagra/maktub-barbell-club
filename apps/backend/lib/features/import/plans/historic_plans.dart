import 'package:maktub_backend/features/import/history/history_sheets.dart';
import 'package:maktub_backend/features/import/plans/plan_import_plan.dart';
import 'package:maktub_backend/features/import/plans/plan_sheets.dart';
import 'package:maktub_core/maktub_core.dart';

/// Prefix of the sheet ids of the plans built from the `historico` rows: `historico-2025-05`.
const historicPlanPrefix = 'historico-';

/// The sheet id of the history plan of [date]'s month.
String historicPlanId(DateTime date) => '$historicPlanPrefix${aIsoFecha(date).substring(0, 7)}';

/// The month (`yyyy-MM`) of a history plan's sheet id, or null if it is not one.
String? historicMonth(String sheetPlanId) =>
    sheetPlanId.startsWith(historicPlanPrefix) ? sheetPlanId.substring(historicPlanPrefix.length) : null;

/// Where a `historico` Registro row sits in its month's plan: the columns [PlanImportPlan.locate] takes.
class HistoricPosition {
  const HistoricPosition({required this.variant, required this.block, required this.order});

  final String variant;
  final String block;
  final int order;
}

/// The plans built from the `historico` rows of Registro, and where each row went.
class HistoricPlans {
  final plans = <SheetPlan>[];

  /// Registro line → its position.
  final positions = <int, HistoricPosition>{};

  /// Sheet plan id → the sheet athlete ids that recorded in it.
  final athletes = <String, Set<String>>{};
  final notes = <String>[];
}

/// One plan per calendar month of the `historico` rows ([legacyHistoryPlan]), in the shape E8.4 builds from Planes
/// (pure, no I/O):
///
/// - **Weeks.** One week model per `semana` that has rows (`s1`..`s4`, "Semana N"); a week with no rows repeats the
///   last one before it, so the cycle has its four weeks.
/// - **Days.** The `dia` numbers; each week keeps only the days it has ([SheetPlan.history]).
/// - **Blocks.** The old `principal` block held everything in the oldest months, so a row of `principal` whose
///   exercise is neither primary nor secondary in the catalog ([categoriesOf]) goes to the accessories (`final`)
///   or the warm-up, by its category. Then the same layout as E8.4 (D16). The exercises of a block keep the order
///   they first appear in.
/// - **Sets.** One per `serie` of either athlete, with the reps one of them recorded. No % (the sheet never had
///   one): the plan is published in history mode.
HistoricPlans historicPlans(List<SheetRecordRow> rows, {required List<String> Function(String exercise) categoriesOf}) {
  final out = HistoricPlans();
  final byMonth = <String, List<SheetRecordRow>>{};
  for (final r in rows.where((r) => r.session.plan == legacyHistoryPlan)) {
    byMonth.putIfAbsent(historicPlanId(r.session.date), () => []).add(r);
  }
  for (final MapEntry(key: id, value: monthRows) in byMonth.entries) {
    monthRows.sort((a, b) => a.line.compareTo(b.line));
    final month = historicMonth(id)!;
    final plan = SheetPlan(
      id: id,
      name: 'Histórico $month',
      active: false,
      start: '$month-01',
      sequence: <String>[],
      line: monthRows.first.line,
      history: true,
    );
    final orders = <String, List<String>>{};
    final sets = <String, SheetSetRow>{};
    final weeks = <int>{};
    final days = <int>{};
    for (final r in monthRows) {
      out.athletes.putIfAbsent(id, () => {}).add(r.athlete);
      final categories = categoriesOf(r.exercise);
      var block = r.block;
      if (block == SheetBlocks.main && !categories.contains('primario') && !categories.contains('secundario')) {
        if (categories.contains('accesorio')) {
          block = SheetBlocks.accessories;
        } else if (categories.contains('calentamiento')) {
          block = SheetBlocks.warmUp;
        }
      }
      final variant = 's${r.session.week}';
      final inBlock = orders.putIfAbsent('$variant|${r.session.day}|$block', () => []);
      if (!inBlock.contains(r.exercise)) inBlock.add(r.exercise);
      final order = inBlock.indexOf(r.exercise) + 1;
      out.positions[r.line] = HistoricPosition(variant: variant, block: block, order: order);
      weeks.add(r.session.week);
      days.add(r.session.day);
      final serie = r.set;
      if (serie == null) continue;
      final key = '$variant|${r.session.day}|$block|$order|${r.exercise}|$serie';
      final previous = sets[key];
      if (previous == null || (previous.reps == null && r.reps != null)) {
        sets[key] = SheetSetRow(
          line: previous?.line ?? r.line,
          day: r.session.day,
          block: block,
          group: '',
          order: order,
          exercise: r.exercise,
          variant: variant,
          set: serie,
          reps: r.reps,
        );
      }
    }
    final present = weeks.toList()..sort();
    plan.weekModels.addAll([for (final w in present) SheetWeekModel(id: 's$w', name: 'Semana $w', archived: false)]);
    final repeated = <int>[];
    for (var w = 1; w <= planCycleWeeks; w++) {
      if (weeks.contains(w)) {
        plan.sequence.add('s$w');
      } else {
        repeated.add(w);
        plan.sequence.add('s${present.lastWhere((p) => p < w, orElse: () => present.first)}');
      }
    }
    if (repeated.isNotEmpty) {
      out.notes.add(
        'plan "${plan.name}" ($id): Registro no tiene la semana ${repeated.join(' ni la ')}; para que el ciclo '
        'tenga cuatro semanas repite la anterior.',
      );
    }
    plan.days.addAll([
      for (final d in days.toList()..sort())
        SheetDay(day: d, primary: null, stretching: const [], warmUp: const [], line: monthRows.first.line),
    ]);
    plan.rows.addAll(sets.values);
    out.plans.add(plan);
  }
  return out;
}
