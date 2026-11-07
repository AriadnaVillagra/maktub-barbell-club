import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_ui/maktub_ui.dart';

import 'fuentes.dart';

void main() {
  test('las fuentes están empaquetadas en el paquete, con su licencia (criterio 9)', () {
    for (final archivos in archivosDeFuentes.values) {
      for (final archivo in archivos) {
        expect(File('assets/fuentes/$archivo').existsSync(), isTrue, reason: archivo);
      }
    }
    expect(File('assets/fuentes/OFL-Inter.txt').existsSync(), isTrue);
    expect(File('assets/fuentes/OFL-BarlowCondensed.txt').existsSync(), isTrue);

    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final archivos in archivosDeFuentes.values) {
      for (final archivo in archivos) {
        expect(pubspec, contains('assets/fuentes/$archivo'), reason: 'declarar $archivo en pubspec');
      }
    }
  });

  test('Inter en el texto y Barlow Condensed en números y títulos de marca', () {
    final tema = TemaMaktub.oscuro();
    expect(tema.textTheme.bodyMedium!.fontFamily, Familias.texto);
    expect(tema.textTheme.titleLarge!.fontFamily, Familias.texto);
    expect(tema.textTheme.displayLarge!.fontFamily, Familias.numeros);
    final n = tema.extension<NumerosMaktub>()!;
    for (final estilo in [n.peso, n.reloj, n.grande, n.medio, n.chico]) {
      expect(estilo.fontFamily, Familias.numeros);
    }
  });

  test('todos los estilos de texto usan cifras tabulares', () {
    final t = TemaMaktub.claro().textTheme;
    final estilos = [
      t.displayLarge, t.displayMedium, t.displaySmall, t.headlineLarge, t.headlineMedium, t.headlineSmall,
      t.titleLarge, t.titleMedium, t.titleSmall, t.bodyLarge, t.bodyMedium, t.bodySmall,
      t.labelLarge, t.labelMedium, t.labelSmall,
    ];
    for (final estilo in estilos) {
      expect(estilo!.fontFeatures, contains(const FontFeature.tabularFigures()));
    }
  });
}
