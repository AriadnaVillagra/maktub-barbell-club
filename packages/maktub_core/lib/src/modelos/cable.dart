/// Enums con un nombre estable en el cable (JSON / Mongo), independiente del nombre en Dart.
abstract interface class ConCable {
  String get cable;
}

/// Busca el valor cuyo [ConCable.cable] coincide (sin distinguir mayúsculas ni espacios).
T desdeCable<T extends ConCable>(List<T> valores, Object? valor, String tipo) {
  final texto = '${valor ?? ''}'.trim().toLowerCase();
  for (final v in valores) {
    if (v.cable == texto) return v;
  }
  throw FormatException('$tipo desconocido: "$valor"');
}
