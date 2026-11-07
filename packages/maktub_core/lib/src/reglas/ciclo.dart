import 'fechas.dart';

/// Dónde cae una fecha dentro de un plan que repite sus 4 semanas sin fin desde la fecha de
/// inicio de la asignación. Qué modelo de semana toca lo decide la asignación del plan
/// (semana 1..4 → modelo), que llega con F5/F7.
class UbicacionEnCiclo {
  const UbicacionEnCiclo({required this.ciclo, required this.semana});

  /// Antes del inicio, todo cae en ciclo 1, semana 1.
  factory UbicacionEnCiclo.desdeFechas({required DateTime inicio, required DateTime fecha}) {
    final dias = soloFecha(fecha).difference(soloFecha(inicio)).inDays;
    final semanasCorridas = dias < 0 ? 0 : dias ~/ 7;
    return UbicacionEnCiclo(ciclo: semanasCorridas ~/ 4 + 1, semana: semanasCorridas % 4 + 1);
  }

  final int ciclo;

  /// 1 a 4.
  final int semana;

  @override
  bool operator ==(Object other) => other is UbicacionEnCiclo && other.ciclo == ciclo && other.semana == semana;

  @override
  int get hashCode => Object.hash(ciclo, semana);

  @override
  String toString() => 'ciclo $ciclo, semana $semana';
}
