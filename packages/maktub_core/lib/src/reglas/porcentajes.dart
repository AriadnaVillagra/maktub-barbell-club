import 'equipo.dart';

/// Ajuste del día: porcentaje sobre lo planificado (100 = sin cambios).
/// Nunca modifica los RMs guardados: el RM es el dato medido, el ajuste es circunstancial.
abstract final class Ajuste {
  static const neutro = 100;
  static const minimo = 50;
  static const maximo = 150;
  static const paso = 5;

  static int acotar(int valor) => valor.clamp(minimo, maximo);
}

/// Acepta 65 o 0.65 (celda con formato de porcentaje). 0 / nulo → nulo.
double? normalizarPct(num? valor) {
  if (valor == null || valor == 0) return null;
  return valor <= 2 ? (valor * 1000).round() / 10 : valor.toDouble();
}

/// El % del plan corregido por el ajuste vigente, redondeado a centésimas.
double pctEfectivo(double pctPlan, int ajuste) => (pctPlan * ajuste).round() / 100;

/// Peso propuesto para una serie por porcentaje: ajustado al cargable más cercano.
/// Nulo si falta el RM.
///
/// [workFactor] is the athlete's work factor for the exercise as a percent (80 = 80 %), already
/// resolved (see `currentWorkFactor`). The target is `rm × workFactor × pct`, rounded to the nearest
/// loadable weight of [equipo]. 100 is neutral and gives exactly `rm × pct`. Inputs are not modified.
double? pesoPorPorcentaje({
  required double? rm,
  required double pct,
  required Equipo equipo,
  double workFactor = 100,
}) {
  if (rm == null || rm <= 0) return null;
  final base = workFactor == 100 ? rm : rm * workFactor / 100;
  return equipo.masCercano(base * pct / 100);
}

/// % a registrar cuando el atleta escribió el kilaje a mano: sale del peso,
/// para que `rm × pct ≈ peso` siga valiendo en el historial.
double pctDesdePeso(double pesoKg, double rm) => (pesoKg / rm * 10000).round() / 100;
