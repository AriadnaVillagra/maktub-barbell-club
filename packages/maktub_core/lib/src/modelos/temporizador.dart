import 'base.dart';
import 'cable.dart';
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
  final Auditoria? auditoria;

  factory Temporizador.fromJson(Json j) => Temporizador(
    id: '${j['id']}',
    clubId: textoOpcional(j['clubId']) ?? clubPlataforma,
    nombre: '${j['nombre']}',
    tipo: TipoTemporizador.deCable(j['tipo']),
    trabajoSeg: enteroOpcional(j['trabajoSeg']) ?? 0,
    descansoSeg: enteroOpcional(j['descansoSeg']) ?? 0,
    rondas: enteroOpcional(j['rondas']) ?? 1,
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
    'auditoria': auditoria?.toJson(),
  });
}
