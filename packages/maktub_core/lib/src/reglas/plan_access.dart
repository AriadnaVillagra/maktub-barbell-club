/// What a coach can do with a plan of the club, by its visibility (pedido de Ari, 2026-11-19). The backend
/// authorizes with it and the app shows or hides actions with it.
library;

import '../modelos/clubes.dart';
import '../modelos/plan.dart';

/// What [userId], with [roles] in the plan's club, can do with [plan]. Only says something about plans: the
/// caller still needs [Accion.planificar] or [Accion.deletePlan] from the permission matrix.
class PlanAccess {
  const PlanAccess._({required this.see, required this.edit, required this.manage});

  /// Its creator (`auditoria.creadoPor`), the club admins and the platform admins reach it whole, whatever its
  /// visibility.
  factory PlanAccess.of(Plan plan, {required String userId, required Set<Rol> roles, bool isPlatformAdmin = false}) =>
      plan.auditoria.creadoPor == userId || roles.contains(Rol.adminClub) || isPlatformAdmin
      ? const PlanAccess._(see: true, edit: true, manage: true)
      : switch (plan.visibility) {
          PlanVisibility.private => const PlanAccess._(see: false, edit: false, manage: false),
          PlanVisibility.sharedReadOnly => const PlanAccess._(see: true, edit: false, manage: false),
          PlanVisibility.sharedEditable => const PlanAccess._(see: true, edit: true, manage: false),
        };

  /// Listed, read, copied and assigned. A plan the user cannot see does not exist for them (404).
  final bool see;

  /// Saved and published.
  final bool edit;

  /// Deleted, and its visibility changed.
  final bool manage;
}
