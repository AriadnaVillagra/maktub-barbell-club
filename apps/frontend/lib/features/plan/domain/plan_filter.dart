import 'package:maktub_core/maktub_core.dart';

import 'plan_repository.dart';

/// Whether [plan] goes under "Pasados" in the plans list: a history plan, or one whose assignments
/// have all ended. A plan with no assignment yet (a draft or a new plan), or with an active or paused
/// one, is active.
bool isPastPlan(PlanSummary plan, Iterable<Assignment> assignments) {
  if (plan.type == PlanType.history) return true;
  final own = assignments.where((a) => a.planId == plan.id);
  return own.isNotEmpty && own.every((a) => a.status == AssignmentStatus.ended);
}
