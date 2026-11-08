import 'package:maktub_backend/infraestructura/http.dart';
import 'package:maktub_core/maktub_core.dart';

/// A calendar date received as `yyyy-MM-dd` → `DateTime.utc(y, m, d)`. [campo] names the field in the 400 message
/// (`ErrorDeSolicitud`) when [valor] is missing, malformed or not a real date (like `2026-02-30`).
DateTime fechaDeSolicitud(Object? valor, String campo) {
  final mensaje = ErrorDeSolicitud(
    '"$campo" debe ser una fecha con formato yyyy-MM-dd.',
  );
  if (valor is! String) throw mensaje;
  try {
    final fecha = desdeIsoFecha(valor);
    final esReal = valor.trim().length == 10 && aIsoFecha(fecha) == valor.trim();
    if (!esReal) throw mensaje;
    return fecha;
  } on FormatException {
    throw mensaje;
  }
}
