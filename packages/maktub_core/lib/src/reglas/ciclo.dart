import '../modelos/enums.dart';
import 'fechas.dart';

/// Dónde cae una fecha dentro de un plan que repite su mes modelo de 4 semanas.
class UbicacionEnCiclo {
  const UbicacionEnCiclo({required this.ciclo, required this.semana});

  /// Sin fecha de inicio, o antes de ella, todo cae en ciclo 1, semana 1.
  factory UbicacionEnCiclo.desdeFechas({DateTime? inicio, required DateTime fecha}) {
    if (inicio == null) return const UbicacionEnCiclo(ciclo: 1, semana: 1);
    final dias = soloFecha(fecha).difference(soloFecha(inicio)).inDays;
    final semanasCorridas = dias < 0 ? 0 : dias ~/ 7;
    return UbicacionEnCiclo(ciclo: semanasCorridas ~/ 4 + 1, semana: semanasCorridas % 4 + 1);
  }

  final int ciclo;
  final int semana;

  @override
  bool operator ==(Object other) =>
      other is UbicacionEnCiclo && other.ciclo == ciclo && other.semana == semana;

  @override
  int get hashCode => Object.hash(ciclo, semana);

  @override
  String toString() => 'ciclo $ciclo, semana $semana';
}

/// Semanas 1 y 4 → descarga; 2 → carga; 3 → carga2 si el plan la define, si no carga.
Variante varianteDeSemana(int semana, {required bool planTieneCarga2}) => switch (semana) {
      1 || 4 => Variante.descarga,
      2 => Variante.carga,
      3 => planTieneCarga2 ? Variante.carga2 : Variante.carga,
      _ => throw RangeError.range(semana, 1, 4, 'semana'),
    };
