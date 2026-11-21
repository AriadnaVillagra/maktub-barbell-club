import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_ui/maktub_ui.dart';

void main() {
  for (final modo in [ModoApp.entrenamiento, ModoApp.planificacion]) {
    testWidgets('la manija de $modo cumple el tamaño táctil', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TemaMaktub.para(Brightness.dark, modo.densidad),
          home: Scaffold(
            body: ReorderableListView(
              buildDefaultDragHandles: false,
              onReorderItem: (_, _) {},
              children: [
                ManijaArrastre(key: const Key('m'), index: 0),
              ],
            ),
          ),
        ),
      );
      final tamano = tester.getSize(find.byType(ManijaArrastre));
      final minimo = modo == ModoApp.entrenamiento ? 56 : 48;
      expect(tamano.width, greaterThanOrEqualTo(minimo));
      expect(tamano.height, greaterThanOrEqualTo(minimo));
    });
  }
}
