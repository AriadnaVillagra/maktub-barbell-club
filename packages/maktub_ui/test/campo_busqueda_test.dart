import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_ui/maktub_ui.dart';

void main() {
  testWidgets('la X aparece con texto y borra todo lo escrito', (tester) async {
    String? ultimo;
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: CampoBusqueda(hint: 'Buscar', onChanged: (v) => ultimo = v))),
    );
    expect(find.byKey(const Key('busqueda-borrar')), findsNothing);

    await tester.enterText(find.byType(TextField), 'press');
    await tester.pump();
    expect(ultimo, 'press');

    await tester.tap(find.byKey(const Key('busqueda-borrar')));
    await tester.pump();
    expect(ultimo, '');
    expect(find.text('press'), findsNothing);
    expect(find.byKey(const Key('busqueda-borrar')), findsNothing);
  });
}
