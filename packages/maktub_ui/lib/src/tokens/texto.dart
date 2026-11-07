import 'package:flutter/material.dart';

/// Familias tipográficas aprobadas (F17 §6, DS7), empaquetadas en `maktub_ui` (ver pubspec).
/// El prefijo `packages/maktub_ui/` es como Flutter nombra las fuentes de un paquete.
abstract final class Familias {
  /// Inter: todo el texto de la interfaz (400–700).
  static const texto = 'packages/maktub_ui/Inter';

  /// Barlow Condensed: números grandes (peso, reps, cronómetro) y títulos de marca (500–700).
  static const numeros = 'packages/maktub_ui/BarlowCondensed';
}

const _tabulares = [FontFeature.tabularFigures()];

/// Escala numérica aparte de la de texto: kilos, reps y tiempo son lo más importante de la
/// pantalla de entrenamiento. Todas con cifras tabulares, para que no bailen al cambiar.
/// Se lee con `context.numeros`.
@immutable
class NumerosMaktub extends ThemeExtension<NumerosMaktub> {
  const NumerosMaktub({
    required this.peso,
    required this.reloj,
    required this.grande,
    required this.medio,
    required this.chico,
  });

  /// El peso a cargar en entrenamiento, legible a uno o dos metros.
  final TextStyle peso;

  /// El cronómetro grande.
  final TextStyle reloj;
  final TextStyle grande;
  final TextStyle medio;
  final TextStyle chico;

  factory NumerosMaktub.para(Color color) {
    TextStyle estilo(double tamano, FontWeight peso) => TextStyle(
          fontFamily: Familias.numeros,
          fontSize: tamano,
          fontWeight: peso,
          height: 1.05,
          color: color,
          fontFeatures: _tabulares,
        );
    return NumerosMaktub(
      peso: estilo(88, FontWeight.w700),
      reloj: estilo(72, FontWeight.w600),
      grande: estilo(48, FontWeight.w700),
      medio: estilo(32, FontWeight.w600),
      chico: estilo(20, FontWeight.w600),
    );
  }

  @override
  NumerosMaktub copyWith() => this;

  @override
  NumerosMaktub lerp(NumerosMaktub? otro, double t) {
    if (otro == null) return this;
    TextStyle l(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return NumerosMaktub(
      peso: l(peso, otro.peso),
      reloj: l(reloj, otro.reloj),
      grande: l(grande, otro.grande),
      medio: l(medio, otro.medio),
      chico: l(chico, otro.chico),
    );
  }
}

/// Escala de texto de Material 3: Inter en todo, Barlow Condensed en los `display` (títulos de
/// marca), y cifras tabulares siempre, para que los números no se muevan al cambiar.
TextTheme textosMaktub(Brightness brillo, Color color) {
  final base = (brillo == Brightness.dark ? Typography.material2021().white : Typography.material2021().black)
      .apply(fontFamily: Familias.texto, bodyColor: color, displayColor: color);
  TextStyle? tab(TextStyle? s) => s?.copyWith(fontFeatures: _tabulares);
  TextStyle? marca(TextStyle? s) =>
      s?.copyWith(fontFamily: Familias.numeros, fontWeight: FontWeight.w700, fontFeatures: _tabulares);
  return base.copyWith(
    displayLarge: marca(base.displayLarge),
    displayMedium: marca(base.displayMedium),
    displaySmall: marca(base.displaySmall),
    headlineLarge: tab(base.headlineLarge),
    headlineMedium: tab(base.headlineMedium),
    headlineSmall: tab(base.headlineSmall),
    titleLarge: tab(base.titleLarge),
    titleMedium: tab(base.titleMedium),
    titleSmall: tab(base.titleSmall),
    bodyLarge: tab(base.bodyLarge),
    bodyMedium: tab(base.bodyMedium),
    bodySmall: tab(base.bodySmall),
    labelLarge: tab(base.labelLarge),
    labelMedium: tab(base.labelMedium),
    labelSmall: tab(base.labelSmall),
  );
}
