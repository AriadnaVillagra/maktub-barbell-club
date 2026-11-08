import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_ui/maktub_ui.dart';

void main() {
  for (final modo in [ModoApp.entrenamiento, ModoApp.planificacion]) {
    testWidgets(
      'la píldora de $modo cumple el tamaño táctil y avisa el toque',
      (tester) async {
        var toques = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: TemaMaktub.para(Brightness.dark, modo.densidad),
            home: Scaffold(
              body: Center(
                child: PildoraMaktub(
                  texto: 'Día 1',
                  seleccionada: false,
                  onTap: () => toques++,
                ),
              ),
            ),
          ),
        );
        final tamano = tester.getSize(find.byType(PildoraMaktub));
        final minimo = modo == ModoApp.entrenamiento ? 56 : 48;
        expect(tamano.height, greaterThanOrEqualTo(minimo));
        await tester.tap(find.byType(PildoraMaktub));
        expect(toques, 1);
      },
    );
  }
}
