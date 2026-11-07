import 'enums.dart';
import 'json.dart';

/// Atleta con sus RMs vigentes (el más reciente por básico) y los kilos fijos de accesorios.
class Atleta {
  const Atleta({
    required this.id,
    required this.nombre,
    this.rms = const {},
    this.pesosAccesorios = const {},
  });

  final String id;
  final String nombre;
  final Map<Basico, double> rms;

  /// Kilaje fijo por id de ejercicio, para ejercicios sin referencia a un básico.
  final Map<String, double> pesosAccesorios;

  double? rmDe(Basico basico) {
    final rm = rms[basico];
    return rm == null || rm <= 0 ? null : rm;
  }

  factory Atleta.fromJson(Json j) => Atleta(
        id: '${j['id']}',
        nombre: '${j['nombre']}',
        rms: {
          for (final e in ((j['rms'] as Map?) ?? const {}).entries)
            Basico.desdeCable(e.key): numOpcional(e.value) ?? 0,
        },
        pesosAccesorios: {
          for (final e in ((j['pesosAccesorios'] as Map?) ?? const {}).entries)
            if (numOpcional(e.value) != null) '${e.key}': numOpcional(e.value)!,
        },
      );

  Json toJson() => {
        'id': id,
        'nombre': nombre,
        'rms': {for (final e in rms.entries) e.key.cable: e.value},
        'pesosAccesorios': pesosAccesorios,
      };
}

/// Un ejercicio carga por porcentaje de RM si y solo si tiene [referencia].
class Ejercicio {
  const Ejercicio({
    required this.id,
    required this.nombre,
    required this.categoria,
    this.referencia,
    this.notas,
  });

  final String id;
  final String nombre;
  final Categoria categoria;
  final Basico? referencia;
  final String? notas;

  factory Ejercicio.fromJson(Json j) => Ejercicio(
        id: '${j['id']}',
        nombre: '${j['nombre']}',
        categoria: Categoria.desdeCable(j['categoria']),
        referencia: Basico.desdeCableOpcional(j['referencia']),
        notas: textoOpcional(j['notas']),
      );

  Json toJson() => sinNulos({
        'id': id,
        'nombre': nombre,
        'categoria': categoria.cable,
        'referencia': referencia?.cable,
        'notas': notas,
      });
}

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
        tipo: TipoTemporizador.desdeCable(j['tipo']),
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

class Wod {
  const Wod({
    required this.id,
    required this.nombre,
    this.formato,
    this.temporizador,
    this.descripcion,
  });

  final String id;
  final String nombre;
  final String? formato;

  /// Id de [Temporizador].
  final String? temporizador;
  final String? descripcion;

  factory Wod.fromJson(Json j) => Wod(
        id: '${j['id']}',
        nombre: '${j['nombre']}',
        formato: textoOpcional(j['formato']),
        temporizador: textoOpcional(j['temporizador']),
        descripcion: textoOpcional(j['descripcion']),
      );

  Json toJson() => sinNulos({
        'id': id,
        'nombre': nombre,
        'formato': formato,
        'temporizador': temporizador,
        'descripcion': descripcion,
      });
}
