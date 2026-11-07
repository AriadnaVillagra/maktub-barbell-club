import 'package:flutter/material.dart';

/// Planificación es densa (tablet/escritorio, mucho a la vez); entrenamiento es grande
/// (celular en una mano, con tiza, leído a distancia).
enum Densidad {
  planificacion(tactilMinimo: 48, separacion: 8),
  entrenamiento(tactilMinimo: 56, separacion: 12);

  const Densidad({required this.tactilMinimo, required this.separacion});

  /// Lado mínimo de cualquier control táctil, en dp.
  final double tactilMinimo;

  /// Separación mínima entre controles táctiles vecinos.
  final double separacion;
}

/// La densidad activa, como extensión del tema. Se lee con `context.densidad`.
@immutable
class DensidadMaktub extends ThemeExtension<DensidadMaktub> {
  const DensidadMaktub(this.densidad);

  final Densidad densidad;

  @override
  DensidadMaktub copyWith({Densidad? densidad}) => DensidadMaktub(densidad ?? this.densidad);

  @override
  DensidadMaktub lerp(DensidadMaktub? otro, double t) => t < 0.5 || otro == null ? this : otro;
}

/// Duraciones y curvas estándar. Respetan "reducir movimiento" del sistema.
abstract final class Movimiento {
  static const corto = Duration(milliseconds: 150);
  static const medio = Duration(milliseconds: 250);
  static const largo = Duration(milliseconds: 400);
  static const curva = Curves.easeOutCubic;
  static const curvaEnfatizada = Curves.easeInOutCubicEmphasized;

  /// [duracion], o cero si el usuario pidió reducir el movimiento.
  static Duration en(BuildContext context, Duration duracion) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false ? Duration.zero : duracion;
}
