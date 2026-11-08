import 'package:maktub_core/maktub_core.dart';

/// The plan being edited, in memory: the editable structure (name, week models, the 4-position
/// assignment and the days of each model) on top of the [base] plan it came from.
///
/// Immutable; every operation returns a new draft, and an operation that would break a structural limit
/// (7 days, 4 weeks) returns the same draft. Blocks are edited here (E5.6) and prescriptions are added and removed (E5.7);
/// E5.8 edits the sets.
class PlanDraft {
  const PlanDraft({
    required this.base,
    required this.weekModels,
    required this.assignment,
  });

  /// Starts editing [plan]. A missing or short assignment is padded with unassigned weeks; an id that
  /// points to no model is cleared.
  factory PlanDraft.from(Plan plan) {
    final ids = {for (final m in plan.weekModels) m.id};
    return PlanDraft(
      base: plan,
      weekModels: plan.weekModels,
      assignment: [
        for (var w = 0; w < planCycleWeeks; w++)
          w < plan.weekAssignment.length && ids.contains(plan.weekAssignment[w])
              ? plan.weekAssignment[w]
              : null,
      ],
    );
  }

  final Plan base;
  final List<WeekModel> weekModels;

  /// One entry per week of the cycle: the id of a week model, or null while unassigned.
  final List<String?> assignment;

  /// Whether the structure differs from the plan it came from.
  bool get isDirty {
    final original = PlanDraft.from(base);
    return !_sameModels(original.weekModels, weekModels) ||
        !_sameList(original.assignment, assignment);
  }

  /// The plan with the edited structure, ready for E5.9 to validate and save. An unassigned week
  /// becomes an empty id, which `validatePlan` reports.
  Plan toPlan() => Plan(
    id: base.id,
    clubId: base.clubId,
    name: base.name,
    type: base.type,
    weekModels: weekModels,
    weekAssignment: [for (final a in assignment) a ?? ''],
    auditoria: base.auditoria,
  );

  WeekModel? modelById(String? id) {
    for (final m in weekModels) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// The name the next model gets by default: the first of A, B, C... not in use.
  String get suggestedModelName {
    final used = {for (final m in weekModels) m.name.trim().toUpperCase()};
    for (var i = 0; i < 26; i++) {
      final letter = String.fromCharCode(65 + i);
      if (!used.contains(letter)) return letter;
    }
    return 'Modelo ${weekModels.length + 1}';
  }

  /// Adds a week model with one empty day (the minimum a model needs).
  PlanDraft addModel(String name) {
    final taken = {for (final m in weekModels) m.id};
    var n = weekModels.length + 1;
    while (taken.contains('m$n')) {
      n++;
    }
    return _copy(
      models: [
        ...weekModels,
        WeekModel(id: 'm$n', name: name.trim(), days: const [PlanDay()]),
      ],
    );
  }

  PlanDraft renameModel(String id, String name) => _mapModel(
    id,
    (m) => WeekModel(id: m.id, name: name.trim(), days: m.days),
  );

  /// Removes the model; the weeks assigned to it become unassigned.
  PlanDraft removeModel(String id) => _copy(
    models: [
      for (final m in weekModels)
        if (m.id != id) m,
    ],
    assignment: [
      for (final a in assignment)
        if (a == id) null else a,
    ],
  );

  /// Assigns [modelId] (or null) to the 0-based [week]. A model can repeat.
  PlanDraft assign(int week, String? modelId) {
    if (week < 0 || week >= planCycleWeeks) return this;
    if (modelId != null && modelById(modelId) == null) return this;
    return _copy(assignment: [...assignment]..[week] = modelId);
  }

  bool canAddDay(String modelId) =>
      (modelById(modelId)?.days.length ?? maxDaysPerWeek) < maxDaysPerWeek;

  bool canRemoveDay(String modelId) =>
      (modelById(modelId)?.days.length ?? minDaysPerWeek) > minDaysPerWeek;

  PlanDraft addDay(String modelId) => !canAddDay(modelId)
      ? this
      : _mapModel(
          modelId,
          (m) => WeekModel(
            id: m.id,
            name: m.name,
            days: [...m.days, const PlanDay()],
          ),
        );

  PlanDraft removeDay(String modelId, int index) {
    final model = modelById(modelId);
    if (model == null || index < 0 || index >= model.days.length) return this;
    if (!canRemoveDay(modelId)) return this;
    return _mapModel(
      modelId,
      (m) =>
          WeekModel(id: m.id, name: m.name, days: [...m.days]..removeAt(index)),
    );
  }

  /// Moves the day at [from] so it ends up at index [to] (both 0-based, inside the list).
  PlanDraft moveDay(String modelId, int from, int to) {
    final model = modelById(modelId);
    if (model == null) return this;
    final n = model.days.length;
    if (from < 0 || from >= n || to < 0 || to >= n || from == to) return this;
    return _mapModel(modelId, (m) {
      final days = [...m.days];
      days.insert(to, days.removeAt(from));
      return WeekModel(id: m.id, name: m.name, days: days);
    });
  }

  /// Appends [block] to the end of the day. The block is added as given: nothing is filled in for it.
  PlanDraft addBlock(String modelId, int day, PlanBlock block) =>
      _mapDay(day: day, modelId, (d) => _withBlocks(d, [...d.blocks, block]));

  PlanDraft removeBlock(String modelId, int day, int index) => _mapDay(
    modelId,
    day: day,
    index: index,
    (d) => _withBlocks(d, [...d.blocks]..removeAt(index)),
  );

  /// Moves the block at [from] so it ends up at index [to] (both 0-based, inside the list).
  PlanDraft moveBlock(String modelId, int day, int from, int to) {
    final n = _dayOf(modelId, day)?.blocks.length ?? 0;
    if (from < 0 || from >= n || to < 0 || to >= n || from == to) return this;
    return _mapDay(modelId, day: day, (d) {
      final blocks = [...d.blocks];
      blocks.insert(to, blocks.removeAt(from));
      return _withBlocks(d, blocks);
    });
  }

  /// Replaces the block at [index] with the result of [change]; its prescriptions are not touched.
  PlanDraft updateBlock(
    String modelId,
    int day,
    int index,
    PlanBlock Function(PlanBlock) change,
  ) => _mapDay(
    modelId,
    day: day,
    index: index,
    (d) => _withBlocks(d, [
      for (final (i, b) in d.blocks.indexed) i == index ? change(b) : b,
    ]),
  );

  /// Appends [prescription] to the end of the block's prescriptions.
  PlanDraft addPrescription(
    String modelId,
    int day,
    int block,
    Prescription prescription,
  ) => updateBlock(
    modelId,
    day,
    block,
    (b) => _withPrescriptions(b, [...b.prescriptions, prescription]),
  );

  PlanDraft removePrescription(String modelId, int day, int block, int index) =>
      updateBlock(
        modelId,
        day,
        block,
        (b) => index < 0 || index >= b.prescriptions.length
            ? b
            : _withPrescriptions(b, [...b.prescriptions]..removeAt(index)),
      );

  /// Replaces the prescription at [index] of the block; sets, note and timer are edited this way (E5.8).
  PlanDraft updatePrescription(
    String modelId,
    int day,
    int block,
    int index,
    Prescription prescription,
  ) => updateBlock(
    modelId,
    day,
    block,
    (b) => index < 0 || index >= b.prescriptions.length
        ? b
        : _withPrescriptions(b, [
            for (final (i, p) in b.prescriptions.indexed)
              i == index ? prescription : p,
          ]),
  );

  PlanBlock _withPrescriptions(PlanBlock b, List<Prescription> list) =>
      PlanBlock(
        name: b.name,
        categoryId: b.categoryId,
        executionMode: b.executionMode,
        athleteMode: b.athleteMode,
        timerId: b.timerId,
        prescriptions: list,
      );

  PlanDay? _dayOf(String modelId, int day) {
    final days = modelById(modelId)?.days;
    return days == null || day < 0 || day >= days.length ? null : days[day];
  }

  PlanDay _withBlocks(PlanDay d, List<PlanBlock> blocks) =>
      PlanDay(name: d.name, blocks: blocks);

  /// Applies [change] to a day; returns this draft if the day (or the block [index], when given) is missing.
  PlanDraft _mapDay(
    String modelId,
    PlanDay Function(PlanDay) change, {
    required int day,
    int? index,
  }) {
    final d = _dayOf(modelId, day);
    if (d == null) return this;
    if (index != null && (index < 0 || index >= d.blocks.length)) return this;
    return _mapModel(
      modelId,
      (m) => WeekModel(
        id: m.id,
        name: m.name,
        days: [
          for (final (i, x) in m.days.indexed) i == day ? change(x) : x,
        ],
      ),
    );
  }

  PlanDraft _mapModel(String id, WeekModel Function(WeekModel) change) =>
      _copy(models: [for (final m in weekModels) m.id == id ? change(m) : m]);

  PlanDraft _copy({List<WeekModel>? models, List<String?>? assignment}) =>
      PlanDraft(
        base: base,
        weekModels: models ?? weekModels,
        assignment: assignment ?? this.assignment,
      );
}

bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// Models are compared by their wire form so edits to blocks (E5.6 on) count as changes too.
bool _sameModels(List<WeekModel> a, List<WeekModel> b) =>
    a.length == b.length &&
    _sameList(
      [for (final m in a) '${m.toJson()}'],
      [for (final m in b) '${m.toJson()}'],
    );
