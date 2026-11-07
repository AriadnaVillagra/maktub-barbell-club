import 'package:flutter/material.dart';

import '../tokens/colores.dart';
import '../tokens/densidad.dart';
import '../tokens/primitivos.dart';
import '../tokens/texto.dart';

/// Capa 3: `ThemeData` de Material 3 armado solo desde tokens. Los componentes de Material
/// quedan configurados acá (tamaños táctiles, formas, bordes), así las pantallas no tocan estilos.
abstract final class TemaMaktub {
  static ThemeData claro({Densidad densidad = Densidad.planificacion}) =>
      _construir(EsquemasMaktub.claro, ColoresMaktub.claro, densidad);

  static ThemeData oscuro({Densidad densidad = Densidad.planificacion}) =>
      _construir(EsquemasMaktub.oscuro, ColoresMaktub.oscuro, densidad);

  static ThemeData para(Brightness brillo, Densidad densidad) =>
      brillo == Brightness.dark ? oscuro(densidad: densidad) : claro(densidad: densidad);

  static ThemeData _construir(ColorScheme esquema, ColoresMaktub colores, Densidad densidad) {
    final oscuro = esquema.brightness == Brightness.dark;
    final tactil = densidad.tactilMinimo;
    final textos = textosMaktub(esquema.brightness, esquema.onSurface);
    final minimo = Size(tactil, tactil);
    const formaControl = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radios.medio)));
    // En oscuro se separan superficies con bordes visibles en lugar de sombras.
    final bordeSuperficie = BorderSide(color: esquema.outlineVariant, width: oscuro ? Borde.fino : 0);

    return ThemeData(
      useMaterial3: true,
      colorScheme: esquema,
      brightness: esquema.brightness,
      textTheme: textos,
      fontFamily: Familias.texto,
      scaffoldBackgroundColor: esquema.surface,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      extensions: [colores, NumerosMaktub.para(esquema.onSurface), DensidadMaktub(densidad)],
      appBarTheme: AppBarTheme(
        backgroundColor: esquema.surface,
        foregroundColor: esquema.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: tactil + Espacio.s,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: esquema.surfaceContainerLow,
        margin: const EdgeInsets.symmetric(vertical: Espacio.xs),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(Radios.medio)),
          side: bordeSuperficie,
        ),
      ),
      // Botón principal: rojo oscuro de marca con texto blanco en los dos temas (F17 §6.2).
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: minimo,
          shape: formaControl,
          backgroundColor: colores.botonPrimario.fondo,
          foregroundColor: colores.botonPrimario.sobre,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(minimumSize: minimo, shape: formaControl)),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: minimo,
          shape: formaControl,
          side: BorderSide(color: esquema.outline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: minimo, shape: formaControl)),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: minimo)),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colores.botonPrimario.fondo,
        foregroundColor: colores.botonPrimario.sobre,
        sizeConstraints: BoxConstraints.tightFor(width: tactil + Espacio.s, height: tactil + Espacio.s),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: esquema.surfaceContainerLow,
        constraints: BoxConstraints(minHeight: tactil),
        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(Radios.chico))),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(Radios.chico)),
          borderSide: BorderSide(color: esquema.outline),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: esquema.outline),
        labelStyle: textos.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: Espacio.s, vertical: Espacio.xs),
      ),
      listTileTheme: ListTileThemeData(
        minTileHeight: tactil,
        contentPadding: const EdgeInsets.symmetric(horizontal: Espacio.l),
        iconColor: esquema.onSurfaceVariant,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: tactil + Espacio.xl,
        backgroundColor: esquema.surfaceContainer,
        indicatorColor: esquema.primaryContainer,
        surfaceTintColor: Colors.transparent,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: esquema.surfaceContainer,
        indicatorColor: esquema.primaryContainer,
        minWidth: tactil + Espacio.xl,
      ),
      dividerTheme: DividerThemeData(color: esquema.outlineVariant, thickness: Borde.fino, space: Espacio.l),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Radios.grande))),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radios.grande))),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      segmentedButtonTheme: SegmentedButtonThemeData(
        // SegmentedButton ignora minimumSize en la altura: se agranda con densidad visual
        // (cada unidad suma 4 dp sobre los 48 de base).
        style: SegmentedButton.styleFrom(
          minimumSize: minimo,
          side: BorderSide(color: esquema.outline),
          visualDensity: VisualDensity(vertical: ((tactil - 48) / 4).clamp(0, VisualDensity.maximumDensity)),
        ),
      ),
    );
  }
}
