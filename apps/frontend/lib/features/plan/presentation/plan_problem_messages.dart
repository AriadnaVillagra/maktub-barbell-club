import 'package:maktub_core/maktub_core.dart';

/// A problem ready to show: [message] says what is wrong, [location] where it is (null for the plan).
class PlanProblemLine {
  const PlanProblemLine(this.message, this.location);

  final String message;
  final String? location;
}

/// The Spanish message of [code]. Exhaustive on purpose: a new `PlanProblemCode` does not compile
/// until it has its message.
String planProblemMessage(PlanProblemCode code) => switch (code) {
  PlanProblemCode.nameEmpty => 'El plan no tiene nombre.',
  PlanProblemCode.weekModelIdDuplicated =>
    'Hay dos modelos de semana con el mismo identificador.',
  PlanProblemCode.weekModelWithoutDays =>
    'El modelo necesita al menos $minDaysPerWeek día.',
  PlanProblemCode.weekModelTooManyDays =>
    'El modelo tiene más de $maxDaysPerWeek días.',
  PlanProblemCode.assignmentWrongLength =>
    'La asignación debe tener $planCycleWeeks semanas.',
  PlanProblemCode.assignmentUnknownModel =>
    'La semana no tiene un modelo de semana asignado.',
  PlanProblemCode.dayWithoutBlocks => 'El día no tiene bloques.',
  PlanProblemCode.blockWithoutCategory => 'El bloque no tiene categoría.',
  PlanProblemCode.blockWithoutPrescriptions => 'El bloque no tiene ejercicios.',
  PlanProblemCode.prescriptionWithoutExercise => 'Falta elegir el ejercicio.',
  PlanProblemCode.prescriptionUnknownExercise =>
    'El ejercicio ya no está en el catálogo.',
  PlanProblemCode.exerciseOutsideBlockCategory =>
    'El ejercicio no pertenece a la categoría del bloque.',
  PlanProblemCode.prescriptionBarNotPositive =>
    'El peso de la barra debe ser mayor que 0.',
  PlanProblemCode.prescriptionWithoutSets => 'El ejercicio no tiene series.',
  PlanProblemCode.setWithoutReps => 'Faltan las repeticiones de la serie.',
  PlanProblemCode.setWithoutPct => 'Falta el % de la serie.',
};

/// Describes [problem] against [plan] (the plan that was validated or sent, so the indices match):
/// "Modelo A › Día 2 › Bloque 1 "Fuerza" › Sentadilla › Serie 3". Indices that point outside the plan fall
/// back to their number, so a stale or foreign index never throws.
PlanProblemLine describePlanProblem(
  PlanProblem problem,
  Plan plan, {
  required String? Function(String exerciseId) exerciseName,
}) {
  final parts = <String>[];
  final modelIndex = problem.weekModelIndex;
  final model = modelIndex != null && modelIndex < plan.weekModels.length
      ? plan.weekModels[modelIndex]
      : null;
  final week = problem.assignmentIndex;
  if (week != null) parts.add('Semana ${week + 1}');
  if (modelIndex != null) {
    final name = model?.name.trim() ?? '';
    parts.add('Modelo ${name.isEmpty ? modelIndex + 1 : name}');
  }
  final dayIndex = problem.dayIndex;
  final day = dayIndex != null && model != null && dayIndex < model.days.length
      ? model.days[dayIndex]
      : null;
  if (dayIndex != null) parts.add(day?.name ?? 'Día ${dayIndex + 1}');
  final blockIndex = problem.blockIndex;
  final block =
      blockIndex != null && day != null && blockIndex < day.blocks.length
      ? day.blocks[blockIndex]
      : null;
  if (blockIndex != null) {
    final name = block?.name.trim() ?? '';
    parts.add(
      name.isEmpty
          ? 'Bloque ${blockIndex + 1}'
          : 'Bloque ${blockIndex + 1} "$name"',
    );
  }
  final prescriptionIndex = problem.prescriptionIndex;
  if (prescriptionIndex != null) {
    final prescription =
        block != null && prescriptionIndex < block.prescriptions.length
        ? block.prescriptions[prescriptionIndex]
        : null;
    final id = prescription?.exerciseId;
    parts.add(
      (id == null ? null : exerciseName(id) ?? id) ??
          'Ejercicio ${prescriptionIndex + 1}',
    );
  }
  final setIndex = problem.setIndex;
  if (setIndex != null) parts.add('Serie ${setIndex + 1}');
  return PlanProblemLine(
    planProblemMessage(problem.code),
    parts.isEmpty ? null : parts.join(' › '),
  );
}
