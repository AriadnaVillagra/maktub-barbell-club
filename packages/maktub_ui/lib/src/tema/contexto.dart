import 'package:flutter/material.dart';

import '../tokens/colores.dart';
import '../tokens/densidad.dart';
import '../tokens/primitivos.dart';
import '../tokens/texto.dart';

/// Acceso corto a los tokens del tema activo: `context.colores.turnoActivo`, `context.numeros.peso`…
extension TokensMaktub on BuildContext {
  ColorScheme get esquema => Theme.of(this).colorScheme;
  TextTheme get textos => Theme.of(this).textTheme;
  ColoresMaktub get colores => Theme.of(this).extension<ColoresMaktub>()!;
  NumerosMaktub get numeros => Theme.of(this).extension<NumerosMaktub>()!;
  Densidad get densidad => Theme.of(this).extension<DensidadMaktub>()?.densidad ?? Densidad.planificacion;
  TamanoPantalla get tamanoPantalla => TamanoPantalla.para(MediaQuery.sizeOf(this).width);
}
