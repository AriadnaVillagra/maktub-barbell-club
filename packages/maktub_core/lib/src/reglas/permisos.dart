/// Matriz de permisos de F1 (docs/features/F1-clubes-usuarios-acceso.md, "Matriz de permisos").
/// La usan el backend para autorizar y la app para mostrar u ocultar acciones.
library;

import '../modelos/base.dart';
import '../modelos/clubes.dart';

/// Una acción por fila de la matriz.
enum Accion {
  /// Ver catálogo, planes asignados y sus sesiones, y usar los temporizadores del club.
  verCatalogoYPlanes,

  /// Registrar lo suyo y lo de compañeros de su sesión (en el club personal, solo lo suyo).
  registrar,
  verReportesPropios,

  /// Editar referencias (RMs, marcas), factores y kilajes. El coach, las de todos; en el club personal, las propias.
  editarReferencias,

  /// Planificar y asignar, y mantener la biblioteca de WoDs.
  planificar,

  /// Delete a plan with its assignments; what was recorded with it stays (E8.9).
  deletePlan,

  /// Create, edit, archive and delete what the club's catalog adds to the default one: exercises (including marking
  /// them with weight), categories and timers. Equipment is apart ([editarEquipo]).
  editarCatalogoClub,

  /// Read the sheet and the history of any athlete of the club.
  verReportesDeTodos,

  /// Change the club's equipment (bar, plates, collars).
  editarEquipo,

  /// Registrar miembros y cambiar sus roles.
  gestionarMiembros,

  /// Only in the personal club: follow the platform's default plans.
  seguirPlanPorDefecto,

  /// Editar el catálogo base y la biblioteca de planes.
  editarPlataforma,

  /// See the pending club requests and approve or reject them.
  reviewClubRequests,

  /// List every club of the platform, to enter any of them for support.
  listAllClubs,
}

/// The permission levels inside a club, from less to more (pedido de Ari, 2026-11-21). Each level can do what
/// it adds plus everything the levels below it can ([actionsOf]).
enum PermissionLevel {
  /// Only what is theirs: the plan of the day, their history and profile, the club's timers, the whole
  /// Training screen.
  athlete({Accion.verCatalogoYPlanes, Accion.registrar, Accion.verReportesPropios}),

  /// What the role needs: plans, assignments, WoDs, exercises, categories, timers, references, and every
  /// athlete's sheet and history. Not the equipment nor the members.
  coach({
    Accion.editarReferencias,
    Accion.planificar,
    Accion.deletePlan,
    Accion.editarCatalogoClub,
    Accion.verReportesDeTodos,
  }),

  /// Everything in their club: also the equipment and the members.
  clubAdmin({Accion.editarEquipo, Accion.gestionarMiembros}),

  /// Everything in every club, even without a membership (support), plus what belongs to the platform.
  platform({Accion.editarPlataforma, Accion.reviewClubRequests, Accion.listAllClubs});

  const PermissionLevel(this.adds);

  /// What this level adds to the ones below it.
  final Set<Accion> adds;

  /// The level of someone with [roles] in a club: the highest one any role gives, and [platform] for a platform
  /// admin whatever the roles. Null without roles and without the flag.
  static PermissionLevel? of(Set<Rol> roles, {bool isPlatformAdmin = false}) {
    if (isPlatformAdmin) return platform;
    if (roles.contains(Rol.adminClub)) return clubAdmin;
    if (roles.contains(Rol.coach)) return coach;
    if (roles.contains(Rol.atleta)) return athlete;
    return null;
  }
}

/// Everything [level] can do: what it adds and what every lower level can do.
Set<Accion> actionsOf(PermissionLevel level) => {
  for (final l in PermissionLevel.values)
    if (l.index <= level.index) ...l.adds,
};

/// Actions that belong to the platform, not to a club: they depend only on the platform admin flag.
final platformActions = PermissionLevel.platform.adds;

/// Whether a user with [isPlatformAdmin] can do the platform action [action]. Club actions are not answered
/// here: they go through [puede].
bool canOnPlatform(Accion action, {required bool isPlatformAdmin}) =>
    platformActions.contains(action) && isPlatformAdmin;

/// What the personal club allows, whatever the roles: it is for training alone, so nobody plans there.
const _personal = {
  Accion.verCatalogoYPlanes,
  Accion.registrar,
  Accion.verReportesPropios,
  Accion.editarReferencias,
  Accion.seguirPlanPorDefecto,
};

/// Si alguien con [roles] en un club de [tipo] puede hacer [accion].
///
/// In a club, the level ([PermissionLevel.of]) decides: each one includes the ones below. A platform admin can do
/// everything in any club, even without a membership. In the personal club its trimmed capabilities rule,
/// whatever the roles (and for a platform admin too). Platform actions depend only on [esAdminPlataforma].
bool puede(Set<Rol> roles, Accion accion, TipoClub tipo, {bool esAdminPlataforma = false}) {
  if (platformActions.contains(accion)) return esAdminPlataforma;
  final level = PermissionLevel.of(roles, isPlatformAdmin: esAdminPlataforma);
  if (level == null) return false;
  if (tipo == TipoClub.personal) return _personal.contains(accion);
  return actionsOf(level).contains(accion);
}

/// Si puede modificar un elemento del catálogo (ejercicio, categoría, temporizador): lo default solo el
/// administrador de plataforma (el cambio se ve en todos los clubes), lo del club quien tenga
/// [Accion.editarCatalogoClub].
bool puedeEscribirCatalogo(
  DelClub elemento,
  Set<Rol> roles,
  TipoClub tipo, {
  bool esAdminPlataforma = false,
}) => elemento.clubId == clubPlataforma
    ? esAdminPlataforma
    : puede(roles, Accion.editarCatalogoClub, tipo, esAdminPlataforma: esAdminPlataforma);

/// Si dejar a [usuarioId] con [rolesNuevos] deja al club sin ningún administrador activo.
bool dejaSinAdmin(Iterable<Membresia> membresiasDelClub, String usuarioId, Set<Rol> rolesNuevos) {
  if (rolesNuevos.contains(Rol.adminClub)) return false;
  return !membresiasDelClub.any((m) => m.usuarioId != usuarioId && m.activa && m.roles.contains(Rol.adminClub));
}

/// Si dejar a [usuarioId] con [rolesNuevos] (vacío = sale o lo quitan) deja al club sin coach activo.
/// Un club siempre tiene al menos un coach activo.
bool dejaSinCoach(Iterable<Membresia> membresiasDelClub, String usuarioId, Set<Rol> rolesNuevos) {
  if (rolesNuevos.contains(Rol.coach)) return false;
  return !membresiasDelClub.any((m) => m.usuarioId != usuarioId && m.esCoachActivo);
}
