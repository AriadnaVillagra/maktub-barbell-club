import 'package:maktub_core/maktub_core.dart';

/// Wire form of a [PlanProblem] in the `problemas` list of a 422: `codigo` is the [PlanProblemCode] name and
/// the location keys (0-based) are only present when the problem is at that level. Shared by the slices that
/// answer a plan with problems (save and publish) so both speak the same shape.
Json planProblemJson(PlanProblem p) => {
  'codigo': p.code.name,
  if (p.weekModelIndex != null) 'modeloSemana': p.weekModelIndex,
  if (p.assignmentIndex != null) 'semana': p.assignmentIndex,
  if (p.dayIndex != null) 'dia': p.dayIndex,
  if (p.blockIndex != null) 'bloque': p.blockIndex,
  if (p.prescriptionIndex != null) 'prescripcion': p.prescriptionIndex,
  if (p.setIndex != null) 'serie': p.setIndex,
};
