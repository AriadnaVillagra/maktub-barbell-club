/// Clubes, membresías, invitaciones e identidad del atleta (F1; docs/diseno.md, "Club, usuarios y roles").
library;

import 'base.dart';
import 'cable.dart';
import 'json.dart';

enum Rol implements ConCable {
  coach('coach'),
  atleta('atleta');

  const Rol(this.cable);
  @override
  final String cable;

  static Rol deCable(Object? v) => desdeCable(values, v, 'Rol');
}

/// `personal` es el club implícito de cada usuario ("mi entrenamiento"); `club`, uno creado a propósito.
enum TipoClub implements ConCable {
  personal('personal'),
  club('club');

  const TipoClub(this.cable);
  @override
  final String cable;

  static TipoClub deCable(Object? v) => desdeCable(values, v, 'Tipo de club');
}

enum EstadoMembresia implements ConCable {
  activa('activa'),
  terminada('terminada');

  const EstadoMembresia(this.cable);
  @override
  final String cable;

  static EstadoMembresia deCable(Object? v) => desdeCable(values, v, 'Estado de membresía');
}

/// Roles en el cable: lista en el orden de [Rol.values], para que el JSON sea estable.
List<String> rolesACable(Set<Rol> roles) => [for (final r in Rol.values) if (roles.contains(r)) r.cable];

Set<Rol> rolesDeCable(Object? v) => {for (final r in (v as List? ?? const [])) Rol.deCable(r)};

DateTime _instante(Object? v) => DateTime.parse('$v').toUtc();
DateTime? _instanteOpcional(Object? v) => v == null ? null : _instante(v);

/// Unidad de aislamiento. Quién lo creó queda en [auditoria].
class Club {
  const Club({required this.id, required this.nombre, required this.tipo, required this.auditoria});

  final String id;
  final String nombre;
  final TipoClub tipo;
  final Auditoria auditoria;

  /// El club personal tiene un único miembro y no se planifica en él.
  bool get esPersonal => tipo == TipoClub.personal;

  factory Club.fromJson(Json j) => Club(
        id: '${j['id']}',
        nombre: '${j['nombre']}',
        tipo: TipoClub.deCable(j['tipo']),
        auditoria: Auditoria.fromJson((j['auditoria'] as Map).cast<String, dynamic>()),
      );

  Json toJson() => {'id': id, 'nombre': nombre, 'tipo': tipo.cable, 'auditoria': auditoria.toJson()};
}

/// Usuario × club × roles. Única por club y usuario; terminarla corta el acceso pero no borra nada.
class Membresia implements DelClub {
  const Membresia({
    required this.id,
    required this.clubId,
    required this.usuarioId,
    required this.roles,
    required this.estado,
    required this.desde,
    this.hasta,
    required this.auditoria,
  });

  final String id;
  @override
  final String clubId;
  final String usuarioId;
  final Set<Rol> roles;
  final EstadoMembresia estado;

  /// Instantes UTC.
  final DateTime desde;
  final DateTime? hasta;
  final Auditoria auditoria;

  bool get activa => estado == EstadoMembresia.activa;
  bool get esCoachActivo => activa && roles.contains(Rol.coach);

  Membresia copiarCon({Set<Rol>? roles, EstadoMembresia? estado, DateTime? hasta, Auditoria? auditoria}) => Membresia(
        id: id,
        clubId: clubId,
        usuarioId: usuarioId,
        roles: roles ?? this.roles,
        estado: estado ?? this.estado,
        desde: desde,
        hasta: hasta ?? this.hasta,
        auditoria: auditoria ?? this.auditoria,
      );

  factory Membresia.fromJson(Json j) => Membresia(
        id: '${j['id']}',
        clubId: '${j['clubId']}',
        usuarioId: '${j['usuarioId']}',
        roles: rolesDeCable(j['roles']),
        estado: EstadoMembresia.deCable(j['estado']),
        desde: _instante(j['desde']),
        hasta: _instanteOpcional(j['hasta']),
        auditoria: Auditoria.fromJson((j['auditoria'] as Map).cast<String, dynamic>()),
      );

  Json toJson() => sinNulos({
        'id': id,
        'clubId': clubId,
        'usuarioId': usuarioId,
        'roles': rolesACable(roles),
        'estado': estado.cable,
        'desde': desde.toUtc().toIso8601String(),
        'hasta': hasta?.toUtc().toIso8601String(),
        'auditoria': auditoria.toJson(),
      });
}

/// Por qué una invitación se puede o no aceptar. El cable sirve para mostrar un mensaje claro.
enum EstadoInvitacion implements ConCable {
  vigente('vigente'),
  vencida('vencida'),
  revocada('revocada'),
  agotada('agotada');

  const EstadoInvitacion(this.cable);
  @override
  final String cable;

  static EstadoInvitacion deCable(Object? v) => desdeCable(values, v, 'Estado de invitación');
}

/// Invitación del coach a un club. El link contiene el [codigo]. Quién la creó queda en [auditoria].
class Invitacion implements DelClub {
  const Invitacion({
    required this.id,
    required this.clubId,
    required this.codigo,
    required this.roles,
    required this.vence,
    this.usosMaximos,
    this.usos = 0,
    this.revocada = false,
    required this.auditoria,
  });

  final String id;
  @override
  final String clubId;
  final String codigo;

  /// Roles que otorga al aceptarla.
  final Set<Rol> roles;

  /// Instante UTC.
  final DateTime vence;

  /// `null` = sin límite de usos.
  final int? usosMaximos;
  final int usos;
  final bool revocada;
  final Auditoria auditoria;

  /// Revocada pesa más que vencida, y vencida más que agotada.
  EstadoInvitacion estadoEn(DateTime ahora) {
    if (revocada) return EstadoInvitacion.revocada;
    if (!ahora.toUtc().isBefore(vence)) return EstadoInvitacion.vencida;
    final maximo = usosMaximos;
    if (maximo != null && usos >= maximo) return EstadoInvitacion.agotada;
    return EstadoInvitacion.vigente;
  }

  factory Invitacion.fromJson(Json j) => Invitacion(
        id: '${j['id']}',
        clubId: '${j['clubId']}',
        codigo: '${j['codigo']}',
        roles: rolesDeCable(j['roles']),
        vence: _instante(j['vence']),
        usosMaximos: enteroOpcional(j['usosMaximos']),
        usos: enteroOpcional(j['usos']) ?? 0,
        revocada: j['revocada'] == true,
        auditoria: Auditoria.fromJson((j['auditoria'] as Map).cast<String, dynamic>()),
      );

  Json toJson() => sinNulos({
        'id': id,
        'clubId': clubId,
        'codigo': codigo,
        'roles': rolesACable(roles),
        'vence': vence.toUtc().toIso8601String(),
        'usosMaximos': usosMaximos,
        'usos': usos,
        'revocada': revocada,
        'auditoria': auditoria.toJson(),
      });
}

/// Perfil de entrenamiento de un miembro dentro del club. Se crea al obtener el rol `atleta`.
/// Las referencias (RM, marcas, ritmo, FC) son documentos propios y llegan con F3.
class Atleta implements DelClub {
  const Atleta({
    required this.id,
    required this.clubId,
    required this.usuarioId,
    required this.nombreVisible,
    required this.auditoria,
  });

  final String id;
  @override
  final String clubId;
  final String usuarioId;
  final String nombreVisible;
  final Auditoria auditoria;

  factory Atleta.fromJson(Json j) => Atleta(
        id: '${j['id']}',
        clubId: '${j['clubId']}',
        usuarioId: '${j['usuarioId']}',
        nombreVisible: '${j['nombreVisible']}',
        auditoria: Auditoria.fromJson((j['auditoria'] as Map).cast<String, dynamic>()),
      );

  Json toJson() => {
        'id': id,
        'clubId': clubId,
        'usuarioId': usuarioId,
        'nombreVisible': nombreVisible,
        'auditoria': auditoria.toJson(),
      };
}
