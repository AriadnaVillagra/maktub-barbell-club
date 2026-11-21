/// Matriz de permisos de F1 (docs/features/F1-clubes-usuarios-acceso.md, "Matriz de permisos").
/// La usan el backend para autorizar y la app para mostrar u ocultar acciones.
library;

import '../modelos/base.dart';
import '../modelos/clubes.dart';

/// Una acción por fila de la matriz.
enum Accion {
  /// Ver catálogo, planes asignados y sus sesiones.
  verCatalogoYPlanes,

  /// Registrar lo suyo y lo de compañeros de su sesión (en el club personal, solo lo suyo).
  registrar,
  verReportesPropios,

  /// Editar referencias (RMs, marcas). El coach, las de todos; en el club personal, las propias.
  editarReferencias,

  /// Planificar y asignar.
  planificar,

  /// Delete a plan with its assignments; what was recorded with it stays (E8.9). Coach and club admin.
  deletePlan,

  /// Crear, editar, archivar y borrar lo del club: ejercicios, categorías, temporizadores y equipo.
  editarCatalogoClub,

  /// Crear y editar los ejercicios del club (incluido marcarlos con peso). Coach y administrador del club;
  /// archivar y borrar siguen siendo de [editarCatalogoClub].
  editarEjerciciosClub,
  seguirPlanPorDefecto,

  /// Registrar miembros y cambiar sus roles. Solo el administrador del club.
  gestionarMiembros,
  verReportesDeTodos,

  /// Editar el catálogo base y la biblioteca de planes. Solo el administrador de plataforma.
  editarPlataforma,

  /// See the pending club requests and approve or reject them. Only the platform admin; grants nothing
  /// inside any club.
  reviewClubRequests,
}

/// Actions that belong to the platform, not to a club: they depend only on the platform admin flag.
const platformActions = {Accion.editarPlataforma, Accion.reviewClubRequests};

/// Whether a user with [isPlatformAdmin] can do the platform action [action]. Club actions are never
/// allowed here: they need a membership ([puede]).
bool canOnPlatform(Accion action, {required bool isPlatformAdmin}) =>
    platformActions.contains(action) && isPlatformAdmin;

const _atleta = {Accion.verCatalogoYPlanes, Accion.registrar, Accion.verReportesPropios};

const _coach = {
  Accion.verCatalogoYPlanes,
  Accion.registrar,
  Accion.verReportesPropios,
  Accion.editarReferencias,
  Accion.planificar,
  Accion.deletePlan,
  Accion.editarEjerciciosClub,
  Accion.verReportesDeTodos,
};

const _adminClub = {
  Accion.verCatalogoYPlanes,
  Accion.editarCatalogoClub,
  Accion.editarEjerciciosClub,
  Accion.gestionarMiembros,
  Accion.deletePlan,
};

const _personal = {
  Accion.verCatalogoYPlanes,
  Accion.registrar,
  Accion.verReportesPropios,
  Accion.editarReferencias,
  Accion.seguirPlanPorDefecto,
};

/// Si alguien con [roles] en un club de [tipo] puede hacer [accion].
///
/// En el club personal mandan sus capacidades recortadas, sin importar los roles de la membresía.
/// Las acciones de plataforma ([platformActions]) dependen solo de [esAdminPlataforma], y esa marca no da
/// nada dentro de un club.
bool puede(Set<Rol> roles, Accion accion, TipoClub tipo, {bool esAdminPlataforma = false}) {
  if (platformActions.contains(accion)) return canOnPlatform(accion, isPlatformAdmin: esAdminPlataforma);
  if (roles.isEmpty) return false;
  if (tipo == TipoClub.personal) return _personal.contains(accion);
  return (roles.contains(Rol.coach) && _coach.contains(accion)) ||
      (roles.contains(Rol.atleta) && _atleta.contains(accion)) ||
      (roles.contains(Rol.adminClub) && _adminClub.contains(accion));
}

/// Si puede modificar un elemento del catálogo: lo default solo el administrador de plataforma (el cambio
/// se ve en todos los clubes), lo del club quien tenga [Accion.editarCatalogoClub].
bool puedeEscribirCatalogo(
  DelClub elemento,
  Set<Rol> roles,
  TipoClub tipo, {
  bool esAdminPlataforma = false,
}) => elemento.clubId == clubPlataforma
    ? esAdminPlataforma
    : puede(roles, Accion.editarCatalogoClub, tipo);

/// Como [puedeEscribirCatalogo], pero para crear y editar un ejercicio: lo del club lo puede quien tenga
/// [Accion.editarEjerciciosClub] (coach o administrador). Lo default sigue siendo solo del administrador de plataforma.
bool puedeEscribirEjercicio(
  DelClub ejercicio,
  Set<Rol> roles,
  TipoClub tipo, {
  bool esAdminPlataforma = false,
}) => ejercicio.clubId == clubPlataforma
    ? esAdminPlataforma
    : puede(roles, Accion.editarEjerciciosClub, tipo);

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
