import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_ui/maktub_ui.dart';

/// Criterio 4 de F17: todos los pares texto/fondo de los dos temas pasan WCAG AA.
void main() {
  for (final (nombre, tema) in [('oscuro', TemaMaktub.oscuro()), ('claro', TemaMaktub.claro())]) {
    group('tema $nombre', () {
      final e = tema.colorScheme;
      final c = tema.extension<ColoresMaktub>()!;
      final superficies = {
        'surface': e.surface,
        'surfaceContainerLowest': e.surfaceContainerLowest,
        'surfaceContainerLow': e.surfaceContainerLow,
        'surfaceContainer': e.surfaceContainer,
        'surfaceContainerHigh': e.surfaceContainerHigh,
        'surfaceContainerHighest': e.surfaceContainerHighest,
      };

      void cumple(String par, Color texto, Color fondo, double minimo) {
        final r = contraste(texto, fondo);
        expect(r, greaterThanOrEqualTo(minimo), reason: '$par: ${r.toStringAsFixed(2)}:1 < $minimo:1');
      }

      test('texto sobre todas las superficies', () {
        for (final s in superficies.entries) {
          cumple('onSurface / ${s.key}', e.onSurface, s.value, Wcag.textoNormal);
          cumple('onSurfaceVariant / ${s.key}', e.onSurfaceVariant, s.value, Wcag.textoNormal);
          cumple('primary (texto) / ${s.key}', e.primary, s.value, Wcag.textoNormal);
          cumple('error (texto) / ${s.key}', e.error, s.value, Wcag.textoNormal);
          cumple('exito (texto) / ${s.key}', c.exito.fondo, s.value, Wcag.textoNormal);
          cumple('alerta (texto) / ${s.key}', c.alerta.fondo, s.value, Wcag.textoNormal);
          cumple('enfasis (texto) / ${s.key}', c.enfasis, s.value, Wcag.textoNormal);
          // El acento rojo es para elementos grandes o no textuales (F17 §6.2).
          cumple('acento (no textual) / ${s.key}', c.acento, s.value, Wcag.noTextual);
        }
      });

      test('pares de relleno de Material', () {
        cumple('onPrimary / primary', e.onPrimary, e.primary, Wcag.textoNormal);
        cumple('onPrimaryContainer / primaryContainer', e.onPrimaryContainer, e.primaryContainer, Wcag.textoNormal);
        cumple('onSecondary / secondary', e.onSecondary, e.secondary, Wcag.textoNormal);
        cumple('onSecondaryContainer / secondaryContainer', e.onSecondaryContainer, e.secondaryContainer, Wcag.textoNormal);
        cumple('onTertiary / tertiary', e.onTertiary, e.tertiary, Wcag.textoNormal);
        cumple('onTertiaryContainer / tertiaryContainer', e.onTertiaryContainer, e.tertiaryContainer, Wcag.textoNormal);
        cumple('onError / error', e.onError, e.error, Wcag.textoNormal);
        cumple('onErrorContainer / errorContainer', e.onErrorContainer, e.errorContainer, Wcag.textoNormal);
        cumple('onInverseSurface / inverseSurface', e.onInverseSurface, e.inverseSurface, Wcag.textoNormal);
      });

      test('pares propios', () {
        final pares = {
          'botonPrimario': c.botonPrimario,
          'exito': c.exito,
          'exitoContenedor': c.exitoContenedor,
          'alerta': c.alerta,
          'alertaContenedor': c.alertaContenedor,
          'serieHecha': c.serieHecha,
          'seriePendiente': c.seriePendiente,
          'turnoActivo': c.turnoActivo,
          'insigniaBase': c.insigniaBase,
          'insigniaPropio': c.insigniaPropio,
          for (var z = 1; z <= 5; z++) 'zona $z': c.zona(z),
          for (final kg in c.discos.keys) 'disco $kg': c.disco(kg),
          'discoOtro': c.discoOtro,
        };
        for (final p in pares.entries) {
          cumple(p.key, p.value.sobre, p.value.fondo, Wcag.textoNormal);
        }
      });

      test('componentes no textuales (1.4.11)', () {
        cumple('outline / surface', e.outline, e.surface, Wcag.noTextual);
        cumple('serieEditada / surface', c.serieEditada, e.surface, Wcag.noTextual);
        cumple('serieEditada / serie pendiente', c.serieEditada, c.seriePendiente.fondo, Wcag.noTextual);
        cumple('borde de controles (outline) / tarjeta', e.outline, e.surfaceContainerLow, Wcag.noTextual);
      });
    });
  }

  group('reglas de marca (F17 §6.2)', () {
    const maroon = Color(0xFF830000);
    const rojoOscuro = Color(0xFFBC0202);
    final oscuro = TemaMaktub.oscuro();
    final claro = TemaMaktub.claro();

    test('el botón primario es #BC0202 con texto blanco en los dos temas', () {
      for (final tema in [oscuro, claro]) {
        final par = tema.extension<ColoresMaktub>()!.botonPrimario;
        expect(par.fondo, rojoOscuro);
        expect(par.sobre, const Color(0xFFFFFFFF));
      }
    });

    test('fondos aprobados: negro puro en oscuro, neutro 98 con tarjetas blancas en claro', () {
      expect(oscuro.colorScheme.surface, const Color(0xFF000000));
      expect(claro.colorScheme.surface, const Color(0xFFFFF8F6));
      expect(claro.colorScheme.surfaceContainerLow, const Color(0xFFFFFFFF));
    });

    test('el error es naranja, fuera de la familia roja de la marca', () {
      for (final tema in [oscuro, claro]) {
        final matiz = HSVColor.fromColor(tema.colorScheme.error).hue;
        expect(matiz, inInclusiveRange(25, 45), reason: 'matiz $matiz');
      }
    });

    test('en oscuro, #830000 y #BC0202 nunca son color de texto', () {
      final e = oscuro.colorScheme;
      final c = oscuro.extension<ColoresMaktub>()!;
      final textos = [e.primary, e.onSurface, e.onSurfaceVariant, e.secondary, e.error, e.onPrimaryContainer, c.enfasis];
      expect(textos, isNot(contains(maroon)));
      expect(textos, isNot(contains(rojoOscuro)));
    });
  });

  test('contraste: negro sobre blanco es 21:1 y un color consigo mismo 1:1', () {
    expect(contraste(Colors.black, Colors.white), closeTo(21, 0.01));
    expect(contraste(Colors.red, Colors.red), 1);
  });
}
