import 'base.dart';
import 'cable.dart';
import 'catalogo.dart' show CatalogStatus;
import 'json.dart';

/// Modos de temporizador. [trabajo] solo existe como bloque de un [mix].
enum TipoTemporizador implements ConCable {
  /// Un tramo de descanso de duración fija.
  countdown('countdown'),
  emom('emom'),
  tabata('tabata'),
  amrap('amrap'),
  forTime('for_time'),

  /// Un tramo de trabajo de duración fija, dentro de un [mix].
  trabajo('trabajo'),

  /// Secuencia de bloques de los otros modos.
  mix('mix');

  const TipoTemporizador(this.cable);
  @override
  final String cable;

  static TipoTemporizador deCable(Object? v) => desdeCable(values, v, 'Tipo de temporizador');
}

/// Problemas de un temporizador: se devuelven en vez de lanzar.
enum TimerProblem {
  nameEmpty,
  workNotPositive,
  restNegative,
  roundsNotPositive,
  setsNotPositive,
  setRestNegative,
  capNotPositive,
  signalNotPositive,
  blocksEmpty,
  nestedMix,
}

/// Preset reutilizable, base (`clubId` = [clubPlataforma]) o del club. Se expande a una lista de fases
/// (ver `fasesDe`). El ámbito se deduce del `clubId` (`scopeOf`), como en el resto del catálogo.
/// Sin `clubId` explícito es de plataforma; [auditoria] es nula en presets que aún no se guardaron.
class Temporizador implements DelClub {
  const Temporizador({
    required this.id,
    this.clubId = clubPlataforma,
    required this.nombre,
    required this.tipo,
    this.trabajoSeg = 0,
    this.descansoSeg = 0,
    this.rondas = 1,
    this.series = 1,
    this.descansoSeriesSeg = 0,
    this.limiteSeg,
    this.senalCadaSeg,
    this.deathBy = false,
    this.bloques = const [],
    this.estado = CatalogStatus.active,
    this.auditoria,
  });

  final String id;
  @override
  final String clubId;

  /// En un bloque de mix es la etiqueta que se muestra mientras corre, y puede estar vacía.
  final String nombre;
  final TipoTemporizador tipo;

  /// Duración del tramo: minuto del EMOM, trabajo del tabata, duración del AMRAP. No se usa en for time ni mix.
  final int trabajoSeg;
  final int descansoSeg;

  /// En un mix, cuántas veces se repite la secuencia completa de bloques.
  final int rondas;

  /// Cuántas veces se repite el temporizador completo, con [descansoSeriesSeg] entre una y otra.
  final int series;
  final int descansoSeriesSeg;

  /// For time: tope de tiempo. Nulo es sin tope.
  final int? limiteSeg;

  /// For time: cada cuántos segundos suena la señal por intervalo. Nulo es sin señal.
  final int? senalCadaSeg;

  /// EMOM "Death By": sigue hasta que el atleta no llega, sin una cantidad fija de rondas.
  final bool deathBy;

  /// Mix: los bloques, en orden. Nunca otro mix.
  final List<Temporizador> bloques;

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
    series: series,
    descansoSeriesSeg: descansoSeriesSeg,
    limiteSeg: limiteSeg,
    senalCadaSeg: senalCadaSeg,
    deathBy: deathBy,
    bloques: bloques,
    estado: estado ?? this.estado,
    auditoria: auditoria ?? this.auditoria,
  );

  bool get _usaTrabajo => tipo != TipoTemporizador.forTime && tipo != TipoTemporizador.mix;

  /// Vacío si el temporizador es válido. [comoBloque]: dentro de un mix, donde el nombre es opcional.
  List<TimerProblem> validar({bool comoBloque = false}) => {
    if (!comoBloque && nombre.trim().isEmpty) TimerProblem.nameEmpty,
    if (_usaTrabajo && trabajoSeg <= 0) TimerProblem.workNotPositive,
    if (descansoSeg < 0) TimerProblem.restNegative,
    if (rondas < 1) TimerProblem.roundsNotPositive,
    if (series < 1) TimerProblem.setsNotPositive,
    if (descansoSeriesSeg < 0) TimerProblem.setRestNegative,
    if (limiteSeg != null && limiteSeg! <= 0) TimerProblem.capNotPositive,
    if (senalCadaSeg != null && senalCadaSeg! <= 0) TimerProblem.signalNotPositive,
    if (tipo == TipoTemporizador.mix && bloques.isEmpty) TimerProblem.blocksEmpty,
    if (tipo == TipoTemporizador.mix && bloques.any((b) => b.tipo == TipoTemporizador.mix)) TimerProblem.nestedMix,
    if (tipo == TipoTemporizador.mix)
      for (final b in bloques)
        if (b.tipo != TipoTemporizador.mix) ...b.validar(comoBloque: true),
  }.toList();

  factory Temporizador.fromJson(Json j) => Temporizador(
    id: textoOpcional(j['id']) ?? '',
    clubId: textoOpcional(j['clubId']) ?? clubPlataforma,
    nombre: textoOpcional(j['nombre']) ?? '',
    tipo: TipoTemporizador.deCable(j['tipo']),
    trabajoSeg: enteroOpcional(j['trabajoSeg']) ?? 0,
    descansoSeg: enteroOpcional(j['descansoSeg']) ?? 0,
    rondas: enteroOpcional(j['rondas']) ?? 1,
    series: enteroOpcional(j['series']) ?? 1,
    descansoSeriesSeg: enteroOpcional(j['descansoSeriesSeg']) ?? 0,
    limiteSeg: enteroOpcional(j['limiteSeg']),
    senalCadaSeg: enteroOpcional(j['senalCadaSeg']),
    deathBy: j['deathBy'] == true,
    bloques: [for (final b in listaJson(j['bloques'])) Temporizador.fromJson(b)],
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
    'series': series == 1 ? null : series,
    'descansoSeriesSeg': descansoSeriesSeg == 0 ? null : descansoSeriesSeg,
    'limiteSeg': limiteSeg,
    'senalCadaSeg': senalCadaSeg,
    'deathBy': deathBy ? true : null,
    'bloques': bloques.isEmpty ? null : [for (final b in bloques) b.toJson()],
    'estado': estado.cable,
    'auditoria': auditoria?.toJson(),
  });
}
