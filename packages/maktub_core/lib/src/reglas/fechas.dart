/// Fechas de calendario sin hora. Se representan como `DateTime.utc(y, m, d)`
/// para que la diferencia en días no se corra con los cambios de horario.
library;

DateTime soloFecha(DateTime d) => DateTime.utc(d.year, d.month, d.day);

DateTime hoy() => soloFecha(DateTime.now());

String aIsoFecha(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime desdeIsoFecha(String texto) {
  final partes = texto.trim().split('T').first.split('-').map(int.parse).toList();
  if (partes.length != 3) throw FormatException('Fecha inválida: "$texto"');
  return DateTime.utc(partes[0], partes[1], partes[2]);
}

DateTime? desdeIsoFechaOpcional(Object? v) =>
    v == null || '$v'.trim().isEmpty ? null : desdeIsoFecha('$v');
