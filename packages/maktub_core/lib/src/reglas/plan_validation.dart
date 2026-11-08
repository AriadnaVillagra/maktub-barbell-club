/// Plan validations shared by backend and app (E5.1). They return every problem, not just the first.
///
/// Reference: `reference/Plan.html`, `validar()` (name, exercise per day, sets, reps, % on percentage
/// exercises). Translation of its "primary / secondary / accessory" slots (decision D16, approved):
/// "day without primary" becomes "block without category" and "exercise outside the block's category",
/// because the category is what a block uses to say what it is.
library;

import '../modelos/catalogo.dart';
import '../modelos/plan.dart';

/// Base categories whose exercises must have sets. As in the reference, in any other block, such as
/// stretching or warm-up, the exercise alone is enough.
const categoriesRequiringSets = {'primario', 'secundario', 'accesorio'};

/// The base stretching category. A stretching block may have only a note, or nothing at all: it is the
/// one kind of block that can stay without exercises in a finished plan.
const stretchingCategoryId = 'estiramiento';

/// The base WoD category. A WoD block mixes exercises of any category, so it is exempt from the rule
/// that an exercise belongs to its block's category.
const wodCategoryId = 'wod';

enum PlanProblemCode {
  nameEmpty,
  weekModelIdDuplicated,
  weekModelWithoutDays,
  weekModelTooManyDays,
  assignmentWrongLength,
  assignmentUnknownModel,
  dayWithoutBlocks,
  blockWithoutCategory,
  blockWithoutPrescriptions,
  prescriptionWithoutExercise,
  prescriptionUnknownExercise,
  exerciseOutsideBlockCategory,
  prescriptionBarNotPositive,
  prescriptionWithoutSets,
  setWithoutReps,
  setWithoutPct,
}

/// A problem and where it is. Indices are 0-based and null when the problem is above that level
/// (`weekModelIndex` is the position in `Plan.weekModels`; `assignmentIndex` is the week, 0-based).
class PlanProblem {
  const PlanProblem(
    this.code, {
    this.weekModelIndex,
    this.assignmentIndex,
    this.dayIndex,
    this.blockIndex,
    this.prescriptionIndex,
    this.setIndex,
  });

  final PlanProblemCode code;
  final int? weekModelIndex;
  final int? assignmentIndex;
  final int? dayIndex;
  final int? blockIndex;
  final int? prescriptionIndex;
  final int? setIndex;

  /// Whether this stops a plan from being saved. Only what makes the plan unusable as a document does:
  /// everything else marks unfinished work, so a coach can save and continue later.
  bool get blocksSaving =>
      code == PlanProblemCode.nameEmpty ||
      code == PlanProblemCode.weekModelIdDuplicated;

  @override
  bool operator ==(Object other) =>
      other is PlanProblem &&
      other.code == code &&
      other.weekModelIndex == weekModelIndex &&
      other.assignmentIndex == assignmentIndex &&
      other.dayIndex == dayIndex &&
      other.blockIndex == blockIndex &&
      other.prescriptionIndex == prescriptionIndex &&
      other.setIndex == setIndex;

  @override
  int get hashCode => Object.hash(
    code,
    weekModelIndex,
    assignmentIndex,
    dayIndex,
    blockIndex,
    prescriptionIndex,
    setIndex,
  );

  @override
  String toString() =>
      'PlanProblem(${code.name}, model: $weekModelIndex, week: $assignmentIndex, day: $dayIndex, '
      'block: $blockIndex, prescription: $prescriptionIndex, set: $setIndex)';
}

/// Validates [plan]. [exerciseById] resolves catalog exercises (null if unknown); the checks that need the
/// exercise (percentage, reps, category) only run for the ones it finds.
List<PlanProblem> validatePlan(
  Plan plan, {
  required Exercise? Function(String id) exerciseById,
}) {
  final problems = <PlanProblem>[];

  if (plan.name.trim().isEmpty) {
    problems.add(const PlanProblem(PlanProblemCode.nameEmpty));
  }

  final ids = <String>{};
  for (var m = 0; m < plan.weekModels.length; m++) {
    final model = plan.weekModels[m];
    if (!ids.add(model.id)) {
      problems.add(
        PlanProblem(PlanProblemCode.weekModelIdDuplicated, weekModelIndex: m),
      );
    }
    if (model.days.length < minDaysPerWeek) {
      problems.add(
        PlanProblem(PlanProblemCode.weekModelWithoutDays, weekModelIndex: m),
      );
    } else if (model.days.length > maxDaysPerWeek) {
      problems.add(
        PlanProblem(PlanProblemCode.weekModelTooManyDays, weekModelIndex: m),
      );
    }
    for (var d = 0; d < model.days.length; d++) {
      _validateDay(problems, model.days[d], m, d, exerciseById);
    }
  }

  if (plan.weekAssignment.length != planCycleWeeks) {
    problems.add(const PlanProblem(PlanProblemCode.assignmentWrongLength));
  }
  for (var w = 0; w < plan.weekAssignment.length; w++) {
    if (!ids.contains(plan.weekAssignment[w])) {
      problems.add(
        PlanProblem(PlanProblemCode.assignmentUnknownModel, assignmentIndex: w),
      );
    }
  }
  return problems;
}

void _validateDay(
  List<PlanProblem> out,
  PlanDay day,
  int m,
  int d,
  Exercise? Function(String id) exerciseById,
) {
  if (day.blocks.isEmpty) {
    out.add(
      PlanProblem(
        PlanProblemCode.dayWithoutBlocks,
        weekModelIndex: m,
        dayIndex: d,
      ),
    );
  }
  for (var b = 0; b < day.blocks.length; b++) {
    final block = day.blocks[b];
    PlanProblem at(PlanProblemCode code, {int? p, int? s}) => PlanProblem(
      code,
      weekModelIndex: m,
      dayIndex: d,
      blockIndex: b,
      prescriptionIndex: p,
      setIndex: s,
    );

    if (block.categoryId == null) {
      out.add(at(PlanProblemCode.blockWithoutCategory));
    }
    if (block.prescriptions.isEmpty && block.categoryId != stretchingCategoryId) {
      out.add(at(PlanProblemCode.blockWithoutPrescriptions));
    }

    for (var p = 0; p < block.prescriptions.length; p++) {
      final rx = block.prescriptions[p];
      if (rx.barKg != null && !(rx.barKg! > 0)) {
        out.add(at(PlanProblemCode.prescriptionBarNotPositive, p: p));
      }
      final exerciseId = rx.exerciseId;
      if (exerciseId == null) {
        out.add(at(PlanProblemCode.prescriptionWithoutExercise, p: p));
        continue;
      }
      if (rx.sets.isEmpty && categoriesRequiringSets.contains(block.categoryId)) {
        out.add(at(PlanProblemCode.prescriptionWithoutSets, p: p));
      }

      final exercise = exerciseById(exerciseId);
      if (exercise == null) {
        out.add(at(PlanProblemCode.prescriptionUnknownExercise, p: p));
        continue;
      }
      if (block.categoryId != null &&
          block.categoryId != wodCategoryId &&
          !exercise.categoryIds.contains(block.categoryId)) {
        out.add(at(PlanProblemCode.exerciseOutsideBlockCategory, p: p));
      }
      final usesPct = exercise.metrics.contains(Metric.loadPctRm);
      final usesReps = exercise.metrics.contains(Metric.reps);
      for (var s = 0; s < rx.sets.length; s++) {
        final set = rx.sets[s];
        if (usesReps && !set.maxReps && !((set.reps ?? 0) > 0)) {
          out.add(at(PlanProblemCode.setWithoutReps, p: p, s: s));
        }
        if (usesPct && !((set.pct ?? 0) > 0)) {
          out.add(at(PlanProblemCode.setWithoutPct, p: p, s: s));
        }
      }
    }
  }
}
