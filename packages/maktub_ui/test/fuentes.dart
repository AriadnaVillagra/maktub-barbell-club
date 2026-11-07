import 'dart:io';

import 'package:flutter/services.dart';
import 'package:maktub_ui/maktub_ui.dart';

/// Archivos empaquetados por familia (ver pubspec.yaml).
const archivosDeFuentes = {
  Familias.texto: ['Inter-400.ttf', 'Inter-500.ttf', 'Inter-600.ttf', 'Inter-700.ttf'],
  Familias.numeros: ['BarlowCondensed-500.ttf', 'BarlowCondensed-600.ttf', 'BarlowCondensed-700.ttf'],
};

/// Los tests de Flutter usan una fuente de prueba; esto carga las reales para que los goldens
/// muestren la tipografía del sistema de diseño.
Future<void> cargarFuentes() async {
  for (final MapEntry(key: familia, value: archivos) in archivosDeFuentes.entries) {
    final cargador = FontLoader(familia);
    for (final archivo in archivos) {
      cargador.addFont(File('assets/fuentes/$archivo').readAsBytes().then((b) => ByteData.sublistView(b)));
    }
    await cargador.load();
  }
}
