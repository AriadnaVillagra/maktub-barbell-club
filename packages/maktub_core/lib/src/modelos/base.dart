import 'json.dart';

/// Documento que pertenece a un club, la unidad de aislamiento (docs/diseno.md, "Club, usuarios y roles").
/// Lo de plataforma (catálogo base, biblioteca de planes) usa el `clubId` reservado [clubPlataforma].
/// Las únicas entidades globales, sin club, son el usuario y sus sesiones de login.
abstract interface class DelClub {
  String get clubId;
}

/// `clubId` de lo que es de plataforma. Leer de un club es `clubId ∈ {clubPlataforma, club actual}`.
const clubPlataforma = 'plataforma';

/// Quién creó y modificó un documento, y cuándo. Los instantes viajan en ISO 8601 UTC.
class Auditoria {
  const Auditoria({
    required this.creadoPor,
    required this.creadoEn,
    this.modificadoPor,
    this.modificadoEn,
  });

  /// Para un documento nuevo escrito ahora por [usuarioId].
  factory Auditoria.nueva(String usuarioId, {DateTime? ahora}) =>
      Auditoria(creadoPor: usuarioId, creadoEn: (ahora ?? DateTime.now()).toUtc());

  /// Id del usuario.
  final String creadoPor;
  final DateTime creadoEn;
  final String? modificadoPor;
  final DateTime? modificadoEn;

  Auditoria modificada(String usuarioId, {DateTime? ahora}) => Auditoria(
        creadoPor: creadoPor,
        creadoEn: creadoEn,
        modificadoPor: usuarioId,
        modificadoEn: (ahora ?? DateTime.now()).toUtc(),
      );

  factory Auditoria.fromJson(Json j) => Auditoria(
        creadoPor: '${j['creadoPor']}',
        creadoEn: DateTime.parse('${j['creadoEn']}').toUtc(),
        modificadoPor: textoOpcional(j['modificadoPor']),
        modificadoEn: j['modificadoEn'] == null ? null : DateTime.parse('${j['modificadoEn']}').toUtc(),
      );

  Json toJson() => sinNulos({
        'creadoPor': creadoPor,
        'creadoEn': creadoEn.toUtc().toIso8601String(),
        'modificadoPor': modificadoPor,
        'modificadoEn': modificadoEn?.toUtc().toIso8601String(),
      });
}
