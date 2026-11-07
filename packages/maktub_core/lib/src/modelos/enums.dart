/// Enumeraciones del dominio con su nombre en el cable (JSON / Mongo).
library;

T _desdeCable<T extends Enum>(List<T> valores, String Function(T) cable, Object? valor, String tipo) {
  final texto = '${valor ?? ''}'.trim().toLowerCase();
  for (final v in valores) {
    if (cable(v) == texto) return v;
  }
  throw FormatException('$tipo desconocido: "$valor"');
}

/// Los tres levantamientos con RM. Todo ejercicio con carga por porcentaje referencia uno.
enum Basico {
  sentadilla('sentadilla', 'sentadilla'),
  pesoMuerto('peso_muerto', 'peso muerto'),
  bench('bench', 'bench');

  const Basico(this.cable, this.etiqueta);
  final String cable;
  final String etiqueta;

  static Basico desdeCable(Object? v) => _desdeCable(values, (b) => b.cable, v, 'Básico');

  static Basico? desdeCableOpcional(Object? v) =>
      v == null || '$v'.trim().isEmpty ? null : desdeCable(v);
}

enum Categoria {
  primario('primario'),
  secundario('secundario'),
  accesorio('accesorio'),
  calentamiento('calentamiento'),
  estiramiento('estiramiento');

  const Categoria(this.cable);
  final String cable;

  static Categoria desdeCable(Object? v) => _desdeCable(values, (c) => c.cable, v, 'Categoría');
}

/// Semanas 1 y 4 son `descarga`; la 2 `carga`; la 3 `carga2` si el plan la define.
enum Variante {
  descarga('descarga', 'descarga'),
  carga('carga', 'carga'),
  carga2('carga2', 'carga 2');

  const Variante(this.cable, this.etiqueta);
  final String cable;
  final String etiqueta;

  static Variante desdeCable(Object? v) => _desdeCable(values, (x) => x.cable, v, 'Variante');
}

/// Partes de un día. Un plan prescribe series solo en [principal] y [cierre];
/// el registro guarda además lo que se hizo sin carga.
enum Bloque {
  estiramiento('estiramiento', 'Estiramiento'),
  calentamiento('calentamiento', 'Calentamiento'),
  principal('principal', 'Bloque principal'),
  cierre('final', 'Bloque final'),
  wod('wod', 'WoD');

  const Bloque(this.cable, this.etiqueta);
  final String cable;
  final String etiqueta;

  static Bloque desdeCable(Object? v) => _desdeCable(values, (b) => b.cable, v, 'Bloque');
}

enum TipoTemporizador {
  countdown('countdown'),
  emom('emom'),
  tabata('tabata');

  const TipoTemporizador(this.cable);
  final String cable;

  static TipoTemporizador desdeCable(Object? v) =>
      _desdeCable(values, (t) => t.cable, v, 'Tipo de temporizador');
}
