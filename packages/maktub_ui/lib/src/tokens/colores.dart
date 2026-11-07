import 'package:flutter/material.dart';

import 'contraste.dart';
import 'primitivos.dart';

/// Un color de relleno con el color de su contenido encima (texto, ícono).
@immutable
class ParColor {
  const ParColor(this.fondo, this.sobre);

  /// [sobre] se elige automáticamente entre negro y blanco por contraste.
  factory ParColor.auto(Color fondo) => ParColor(fondo, textoSobre(fondo, oscuro: Paleta.negro, claro: Paleta.blanco));

  final Color fondo;
  final Color sobre;

  static ParColor lerp(ParColor a, ParColor b, double t) =>
      ParColor(Color.lerp(a.fondo, b.fondo, t)!, Color.lerp(a.sobre, b.sobre, t)!);
}

/// Capa 2: roles semánticos que Material 3 no tiene. Se leen con `context.colores`.
/// Los roles de Material (`ColorScheme`) se leen con `context.esquema`.
@immutable
class ColoresMaktub extends ThemeExtension<ColoresMaktub> {
  const ColoresMaktub({
    required this.botonPrimario,
    required this.enfasis,
    required this.acento,
    required this.exito,
    required this.exitoContenedor,
    required this.alerta,
    required this.alertaContenedor,
    required this.serieHecha,
    required this.seriePendiente,
    required this.serieEditada,
    required this.turnoActivo,
    required this.zonas,
    required this.discos,
    required this.discoOtro,
    required this.insigniaBase,
    required this.insigniaPropio,
  });

  /// La acción principal: `#BC0202` con texto blanco en los dos temas (F17 §6.2).
  /// Es distinto de `ColorScheme.primary`, que en oscuro es un tono claro para poder ser texto.
  final ParColor botonPrimario;

  /// Texto destacado de marca: `#830000` en claro, el tono 80 de la marca en oscuro.
  final Color enfasis;

  /// Rojo vivo `#FF0000`: turno activo, cronómetro, barras, indicadores. En el tema claro, solo
  /// elementos grandes o no textuales (4:1 sobre blanco).
  final Color acento;

  /// Éxito como color de texto/ícono sobre superficies, y su contenedor.
  final ParColor exito;
  final ParColor exitoContenedor;
  final ParColor alerta;
  final ParColor alertaContenedor;

  /// Fondo y contenido de una serie marcada como hecha (contenedor de marca).
  final ParColor serieHecha;

  /// Fondo y contenido de una serie que falta hacer.
  final ParColor seriePendiente;

  /// Marca (borde, punto) de una serie editada a mano. No textual: contraste ≥ 3 con la superficie.
  final Color serieEditada;

  /// A quién le toca, en modo por turnos: pastilla en el contenedor de marca, con un punto en [acento].
  final ParColor turnoActivo;

  /// Zonas de intensidad Z1..Z5.
  final List<ParColor> zonas;

  /// Colores de discos por peso en kg. Solo para el visor de discos.
  final Map<double, ParColor> discos;

  /// Disco de un peso sin color estándar.
  final ParColor discoOtro;

  /// Catálogo: entrada de plataforma vs propia del club.
  final ParColor insigniaBase;
  final ParColor insigniaPropio;

  ParColor zona(int numero) => zonas[(numero - 1).clamp(0, zonas.length - 1)];

  ParColor disco(double kg) => discos[kg] ?? discoOtro;

  static final _discos = <double, ParColor>{
    25: ParColor.auto(Paleta.disco25),
    20: ParColor.auto(Paleta.disco20),
    15: ParColor.auto(Paleta.disco15),
    10: ParColor.auto(Paleta.disco10),
    5: ParColor.auto(Paleta.disco5),
    2.5: ParColor.auto(Paleta.disco2_5),
    1.5: ParColor.auto(Paleta.disco1_5),
    1.25: ParColor.auto(Paleta.disco1_25),
  };

  static final _zonas = [
    for (final c in [Paleta.zona1, Paleta.zona2, Paleta.zona3, Paleta.zona4, Paleta.zona5]) ParColor.auto(c),
  ];

  static const _botonPrimario = ParColor(Paleta.rojoOscuro, Paleta.blanco);

  static final oscuro = ColoresMaktub(
    botonPrimario: _botonPrimario,
    enfasis: Paleta.marca80,
    acento: Paleta.rojo,
    exito: const ParColor(Paleta.exito80, Paleta.negro),
    exitoContenedor: const ParColor(Paleta.exito30, Paleta.neutro90),
    alerta: const ParColor(Paleta.alerta80, Paleta.negro),
    alertaContenedor: const ParColor(Paleta.alerta30, Paleta.neutro90),
    serieHecha: const ParColor(Paleta.marca20, Paleta.marca90),
    seriePendiente: const ParColor(Paleta.neutro5, Paleta.neutro90),
    serieEditada: Paleta.azul300,
    turnoActivo: const ParColor(Paleta.marca20, Paleta.marca90),
    zonas: _zonas,
    discos: _discos,
    discoOtro: ParColor.auto(Paleta.discoOtro),
    insigniaBase: const ParColor(Paleta.neutro10, Paleta.neutro90),
    insigniaPropio: const ParColor(Paleta.marca20, Paleta.marca90),
  );

  static final claro = ColoresMaktub(
    botonPrimario: _botonPrimario,
    enfasis: Paleta.maroon,
    acento: Paleta.rojo,
    exito: const ParColor(Paleta.exito40, Paleta.blanco),
    exitoContenedor: const ParColor(Paleta.exito90, Paleta.neutro10),
    alerta: const ParColor(Paleta.alerta40, Paleta.blanco),
    alertaContenedor: const ParColor(Paleta.alerta90, Paleta.neutro10),
    serieHecha: const ParColor(Paleta.marca90, Paleta.marca10),
    seriePendiente: const ParColor(Paleta.blanco, Paleta.neutro10),
    serieEditada: Paleta.azul700,
    turnoActivo: const ParColor(Paleta.marca90, Paleta.marca10),
    zonas: _zonas,
    discos: _discos,
    discoOtro: ParColor.auto(Paleta.discoOtro),
    insigniaBase: const ParColor(Paleta.neutro95, Paleta.neutro10),
    insigniaPropio: const ParColor(Paleta.marca90, Paleta.marca10),
  );

  @override
  ColoresMaktub copyWith() => this;

  @override
  ColoresMaktub lerp(ColoresMaktub? otro, double t) {
    if (otro == null) return this;
    ParColor par(ParColor a, ParColor b) => ParColor.lerp(a, b, t);
    Color color(Color a, Color b) => Color.lerp(a, b, t)!;
    return ColoresMaktub(
      botonPrimario: par(botonPrimario, otro.botonPrimario),
      enfasis: color(enfasis, otro.enfasis),
      acento: color(acento, otro.acento),
      exito: par(exito, otro.exito),
      exitoContenedor: par(exitoContenedor, otro.exitoContenedor),
      alerta: par(alerta, otro.alerta),
      alertaContenedor: par(alertaContenedor, otro.alertaContenedor),
      serieHecha: par(serieHecha, otro.serieHecha),
      seriePendiente: par(seriePendiente, otro.seriePendiente),
      serieEditada: color(serieEditada, otro.serieEditada),
      turnoActivo: par(turnoActivo, otro.turnoActivo),
      zonas: [for (var i = 0; i < zonas.length; i++) par(zonas[i], otro.zonas[i])],
      discos: {for (final e in discos.entries) e.key: par(e.value, otro.disco(e.key))},
      discoOtro: par(discoOtro, otro.discoOtro),
      insigniaBase: par(insigniaBase, otro.insigniaBase),
      insigniaPropio: par(insigniaPropio, otro.insigniaPropio),
    );
  }
}

/// Roles de Material 3 asignados según la paleta aprobada (F17 §6, DS6), uno por tema.
abstract final class EsquemasMaktub {
  /// Fondo negro puro, tarjetas en neutro 5. `primary` es el tono 80 de la marca: Material lo usa
  /// como color de texto e íconos, y `#830000`/`#BC0202` no alcanzan contraste como texto sobre oscuro.
  /// El botón principal usa `ColoresMaktub.botonPrimario`.
  static const oscuro = ColorScheme(
    brightness: Brightness.dark,
    primary: Paleta.marca80,
    onPrimary: Paleta.marca20,
    primaryContainer: Paleta.marca20,
    onPrimaryContainer: Paleta.marca90,
    secondary: Paleta.neutroVar80,
    onSecondary: Paleta.neutroVar20,
    secondaryContainer: Paleta.neutroVar30,
    onSecondaryContainer: Paleta.neutroVar90,
    tertiary: Paleta.azul300,
    onTertiary: Paleta.negro,
    tertiaryContainer: Paleta.azul700,
    onTertiaryContainer: Paleta.blanco,
    error: Paleta.error70,
    onError: Paleta.error20,
    errorContainer: Paleta.error20,
    onErrorContainer: Paleta.error90,
    surface: Paleta.negro,
    onSurface: Paleta.neutro90,
    onSurfaceVariant: Paleta.neutroVar80,
    surfaceContainerLowest: Paleta.negro,
    surfaceContainerLow: Paleta.neutro5, // tarjetas
    surfaceContainer: Paleta.neutro10, // superficie alta
    surfaceContainerHigh: Paleta.neutro15,
    surfaceContainerHighest: Paleta.neutro20,
    // `outline` (bordes de controles) necesita 3:1; `outlineVariant` es el borde decorativo aprobado.
    outline: Paleta.neutroVar60,
    outlineVariant: Paleta.neutroVar30,
    inverseSurface: Paleta.neutro90,
    onInverseSurface: Paleta.neutro20,
    inversePrimary: Paleta.rojoOscuro,
    shadow: Paleta.negro,
    scrim: Paleta.negro,
    surfaceTint: Paleta.marca80,
  );

  /// Fondo neutro 98, tarjetas blancas, texto neutro 10, primario `#BC0202`.
  static const claro = ColorScheme(
    brightness: Brightness.light,
    primary: Paleta.rojoOscuro,
    onPrimary: Paleta.blanco,
    primaryContainer: Paleta.marca90,
    onPrimaryContainer: Paleta.marca10,
    secondary: Paleta.neutroVar40,
    onSecondary: Paleta.blanco,
    secondaryContainer: Paleta.neutroVar90,
    onSecondaryContainer: Paleta.neutro10,
    tertiary: Paleta.azul700,
    onTertiary: Paleta.blanco,
    tertiaryContainer: Paleta.azul300,
    onTertiaryContainer: Paleta.negro,
    error: Paleta.error40,
    onError: Paleta.blanco,
    errorContainer: Paleta.error90,
    onErrorContainer: Paleta.error10,
    surface: Paleta.neutro98,
    onSurface: Paleta.neutro10,
    onSurfaceVariant: Paleta.neutroVar30,
    surfaceContainerLowest: Paleta.blanco,
    surfaceContainerLow: Paleta.blanco, // tarjetas
    surfaceContainer: Paleta.neutro95, // superficie alta
    surfaceContainerHigh: Paleta.neutro92,
    surfaceContainerHighest: Paleta.neutro90,
    outline: Paleta.neutroVar50,
    outlineVariant: Paleta.neutroVar80,
    inverseSurface: Paleta.neutro20,
    onInverseSurface: Paleta.neutro95,
    inversePrimary: Paleta.marca80,
    shadow: Paleta.negro,
    scrim: Paleta.negro,
    surfaceTint: Paleta.rojoOscuro,
  );
}
