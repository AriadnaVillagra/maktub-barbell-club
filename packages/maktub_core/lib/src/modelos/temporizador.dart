import 'base.dart';
import 'cable.dart';
import 'catalogo.dart' show CatalogStatus;
import 'json.dart';

/// Formatos que hoy sabe expandir `fasesDe`. AMRAP, for time e intervalos llegan con F8.
enum TipoTemporizador implements ConCable {
  countdown('countdown'),
  emom('emom'),
  tabata('tabata');

  const TipoTemporizador(this.cable);
  @override
  final String cable;

  static TipoTemporizador deCable(Object? v) => desdeCable(values, v, 'Tipo de temporizador');
}

/// Problemas de un temporizador: se devuelven en vez de lanzar.
enum TimerProblem { nameEmpty, workNotPositive, restNegative, roundsNotPositive }

/// Preset reutilizable, base (`clubId` = [clubPlataforma]) o del club. Se expande a una lista de fases
/// (ver `fasesDe`). El ámbito se deduce del `clubId` (`scopeOf`), como en el resto del catálogo.
/// Sin `clubId` explícito es de plataforma; [auditoria] es nula en presets que aún no se guardaron.
class Temporizador implements DelClub {
  const Temporizador({
    required this.id,
    this.clubId = clubPlataforma,
    required this.nombre,
    required this.tipo,
    required this.trabajoSeg,
    this.descansoSeg = 0,
    this.rondas = 1,
    this.estado = CatalogStatus.active,
    this.auditoria,
  });

  final String id;
  @override
  final String clubId;
  final String nombre;
  final TipoTemporizador tipo;
  final int trabajoSeg;
  final int descansoSeg;
  final int rondas;

  /// `archivado` deja de ofrecerse, pero se sigue resolviendo donde ya se usa (F2 §5).
  final CatalogStatus estado;
  final Auditoria? auditoria;

  Temporizador copyWith({
    String? nombre,
    TipoTemporizador? tipo,
    int? trabajoSeg,
    int? descansoSeg,
    int? rondas,
    CatalogStatus? estado,
    Auditoria? auditoria,
  }) => Temporizador(
    id: id,
    clubId: clubId,
    nombre: nombre ?? this.nombre,
    tipo: tipo ?? this.tipo,
    trabajoSeg: trabajoSeg ?? this.trabajoSeg,
    descansoSeg: descansoSeg ?? this.descansoSeg,
    rondas: rondas ?? this.rondas,
    estado: estado ?? this.estado,
    auditoria: auditoria ?? this.auditoria,
  );

  /// Vacío si el temporizador es válido.
  List<TimerProblem> validar() => [
    if (nombre.trim().isEmpty) TimerProblem.nameEmpty,
    if (trabajoSeg <= 0) TimerProblem.workNotPositive,
    if (descansoSeg < 0) TimerProblem.restNegative,
    if (rondas < 1) TimerProblem.roundsNotPositive,
  ];

  factory Temporizador.fromJson(Json j) => Temporizador(
    id: '${j['id']}',
    clubId: textoOpcional(j['clubId']) ?? clubPlataforma,
    nombre: '${j['nombre']}',
    tipo: TipoTemporizador.deCable(j['tipo']),
    trabajoSeg: enteroOpcional(j['trabajoSeg']) ?? 0,
    descansoSeg: enteroOpcional(j['descansoSeg']) ?? 0,
    rondas: enteroOpcional(j['rondas']) ?? 1,
    estado: j['estado'] == null ? CatalogStatus.active : CatalogStatus.deCable(j['estado']),
    auditoria: j['auditoria'] == null ? null : Auditoria.fromJson((j['auditoria'] as Map).cast<String, dynamic>()),
  );

  Json toJson() => sinNulos({
    'id': id,
    'clubId': clubId,
    'nombre': nombre,
    'tipo': tipo.cable,
    'trabajoSeg': trabajoSeg,
    'descansoSeg': descansoSeg,
    'rondas': rondas,
    'estado': estado.cable,
    'auditoria': auditoria?.toJson(),
  });
}
