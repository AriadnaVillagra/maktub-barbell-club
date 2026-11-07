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

/// Preset reutilizable. Se expande a una lista de fases (ver `fasesDe`).
/// Pendiente (F2/F8): pertenencia al club y auditoría, cuando sea un documento del catálogo.
class Temporizador {
  const Temporizador({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.trabajoSeg,
    this.descansoSeg = 0,
    this.rondas = 1,
  });

  final String id;
  final String nombre;
  final TipoTemporizador tipo;
  final int trabajoSeg;
  final int descansoSeg;
  final int rondas;

  factory Temporizador.fromJson(Json j) => Temporizador(
        id: '${j['id']}',
        nombre: '${j['nombre']}',
        tipo: TipoTemporizador.deCable(j['tipo']),
        trabajoSeg: enteroOpcional(j['trabajoSeg']) ?? 0,
        descansoSeg: enteroOpcional(j['descansoSeg']) ?? 0,
        rondas: enteroOpcional(j['rondas']) ?? 1,
      );

  Json toJson() => {
        'id': id,
        'nombre': nombre,
        'tipo': tipo.cable,
        'trabajoSeg': trabajoSeg,
        'descansoSeg': descansoSeg,
        'rondas': rondas,
      };
}
