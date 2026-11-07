@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_ui/maktub_ui.dart';

import 'fuentes.dart';

/// Goldens del muestrario en los dos temas (criterio 8). Regenerar después de un cambio visual
/// intencional con `flutter test --update-goldens --tags golden` y revisar las imágenes.
/// Las imágenes dependen de la plataforma: generarlas y compararlas siempre en la misma (macOS).
void main() {
  setUpAll(cargarFuentes);

  for (final (nombre, tema) in [
    ('oscuro_planificacion', TemaMaktub.oscuro()),
    ('claro_planificacion', TemaMaktub.claro()),
    ('oscuro_entrenamiento', TemaMaktub.oscuro(densidad: Densidad.entrenamiento)),
  ]) {
    testWidgets('muestrario $nombre', (tester) async {
      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      const clave = ValueKey('muestrario');
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: tema,
        home: Scaffold(
          body: SingleChildScrollView(
            child: RepaintBoundary(
              key: clave,
              child: ColoredBox(color: tema.colorScheme.surface, child: const Muestrario()),
            ),
          ),
        ),
      ));

      await expectLater(find.byKey(clave), matchesGoldenFile('goldens/muestrario_$nombre.png'));
    });
  }
}
