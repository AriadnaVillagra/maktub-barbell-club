import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_ui/maktub_ui.dart';

void main() {
  group('tema por modo (criterio 3)', () {
    test('entrenamiento abre en oscuro aunque el sistema esté en claro', () {
      expect(brilloPara(ModoApp.entrenamiento, PreferenciaTema.sistema, Brightness.light), Brightness.dark);
    });

    test('planificación sigue al sistema', () {
      expect(brilloPara(ModoApp.planificacion, PreferenciaTema.sistema, Brightness.light), Brightness.light);
      expect(brilloPara(ModoApp.planificacion, PreferenciaTema.sistema, Brightness.dark), Brightness.dark);
    });

    test('la preferencia del usuario manda en los dos modos', () {
      for (final modo in ModoApp.values) {
        expect(brilloPara(modo, PreferenciaTema.claro, Brightness.dark), Brightness.light);
        expect(brilloPara(modo, PreferenciaTema.oscuro, Brightness.light), Brightness.dark);
      }
    });
  });

  test('los temas traen las extensiones propias', () {
    for (final tema in [TemaMaktub.oscuro(), TemaMaktub.claro(densidad: Densidad.entrenamiento)]) {
      expect(tema.extension<ColoresMaktub>(), isNotNull);
      expect(tema.extension<NumerosMaktub>(), isNotNull);
      expect(tema.extension<DensidadMaktub>(), isNotNull);
    }
  });

  test('los números usan cifras tabulares (criterio 6)', () {
    final n = TemaMaktub.oscuro().extension<NumerosMaktub>()!;
    for (final estilo in [n.peso, n.reloj, n.grande, n.medio, n.chico]) {
      expect(estilo.fontFeatures, contains(const FontFeature.tabularFigures()));
    }
  });

  for (final densidad in Densidad.values) {
    testWidgets('ningún control mide menos de ${densidad.tactilMinimo} dp en ${densidad.name} (criterio 5)',
        (tester) async {
      final claves = List.generate(7, (i) => GlobalKey());
      await tester.pumpWidget(MaterialApp(
        theme: TemaMaktub.oscuro(densidad: densidad),
        home: Scaffold(
          body: Wrap(children: [
            FilledButton(key: claves[0], onPressed: () {}, child: const Text('A')),
            OutlinedButton(key: claves[1], onPressed: () {}, child: const Text('B')),
            TextButton(key: claves[2], onPressed: () {}, child: const Text('C')),
            IconButton(key: claves[3], onPressed: () {}, icon: const Icon(Icons.add)),
            SizedBox(width: 200, child: TextField(key: claves[4])),
            SegmentedButton<int>(
              key: claves[5],
              segments: const [ButtonSegment(value: 1, label: Text('1'))],
              selected: const {1},
              onSelectionChanged: (_) {},
            ),
            SizedBox(width: 300, child: ListTile(key: claves[6], title: const Text('Fila'), onTap: () {})),
          ]),
        ),
      ));

      for (final clave in claves) {
        final tamano = tester.getSize(find.byKey(clave));
        expect(tamano.height, greaterThanOrEqualTo(densidad.tactilMinimo), reason: '${clave.currentWidget.runtimeType}');
        expect(tamano.width, greaterThanOrEqualTo(densidad.tactilMinimo), reason: '${clave.currentWidget.runtimeType}');
      }
    });
  }

  testWidgets('TemaDeModo aplica oscuro y densidad grande a entrenamiento', (tester) async {
    late BuildContext contexto;
    await tester.pumpWidget(MaterialApp(
      theme: TemaMaktub.claro(),
      home: TemaDeModo(
        modo: ModoApp.entrenamiento,
        child: Builder(builder: (c) {
          contexto = c;
          return const SizedBox();
        }),
      ),
    ));
    await tester.pumpAndSettle();

    expect(Theme.of(contexto).brightness, Brightness.dark);
    expect(contexto.densidad, Densidad.entrenamiento);
  });
}
