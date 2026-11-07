import 'dart:math' as math;
import 'dart:ui';

/// Relación de contraste WCAG 2.x entre dos colores opacos (1 a 21).
double contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// WCAG AA: 4.5 para texto normal, 3 para texto grande y componentes no textuales.
abstract final class Wcag {
  static const textoNormal = 4.5;
  static const noTextual = 3.0;
}

/// El color de texto (entre [oscuro] y [claro]) con más contraste sobre [fondo].
Color textoSobre(Color fondo, {required Color oscuro, required Color claro}) =>
    contraste(oscuro, fondo) >= contraste(claro, fondo) ? oscuro : claro;
