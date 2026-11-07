/// Matriz de permisos de F1 (docs/features/F1-clubes-usuarios-acceso.md, "Matriz de permisos").
/// La usan el backend para autorizar y la app para mostrar u ocultar acciones.
library;

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

  /// Planificar, asignar y editar el catálogo del club.
  planificar,
  seguirPlanPorDefecto,

  /// Invitar, quitar miembros y cambiar roles.
  gestionarMiembros,
  verReportesDeTodos,

  /// Editar el catálogo base y la biblioteca de planes. Solo el administrador de plataforma.
  editarPlataforma,
}

const _atleta = {Accion.verCatalogoYPlanes, Accion.registrar, Accion.verReportesPropios};

const _coach = {
  Accion.verCatalogoYPlanes,
  Accion.registrar,
  Accion.verReportesPropios,
  Accion.editarReferencias,
  Accion.planificar,
  Accion.gestionarMiembros,
  Accion.verReportesDeTodos,
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
/// [Accion.editarPlataforma] depende solo de [esAdminPlataforma], y esa marca no da nada dentro de un club.
bool puede(Set<Rol> roles, Accion accion, TipoClub tipo, {bool esAdminPlataforma = false}) {
  if (accion == Accion.editarPlataforma) return esAdminPlataforma;
  if (roles.isEmpty) return false;
  if (tipo == TipoClub.personal) return _personal.contains(accion);
  return (roles.contains(Rol.coach) && _coach.contains(accion)) ||
      (roles.contains(Rol.atleta) && _atleta.contains(accion));
}

/// Si dejar a [usuarioId] con [rolesNuevos] (vacío = sale o lo quitan) deja al club sin coach activo.
/// Un club siempre tiene al menos un coach activo.
bool dejaSinCoach(Iterable<Membresia> membresiasDelClub, String usuarioId, Set<Rol> rolesNuevos) {
  if (rolesNuevos.contains(Rol.coach)) return false;
  return !membresiasDelClub.any((m) => m.usuarioId != usuarioId && m.esCoachActivo);
}
