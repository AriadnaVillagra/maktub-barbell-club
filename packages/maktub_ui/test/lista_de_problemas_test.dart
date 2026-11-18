import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_ui/maktub_ui.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: TemaMaktub.claro(),
    home: Scaffold(body: child),
  ),
);

List<ProblemaMaktub> _problemas(int n) => [
  for (var i = 1; i <= n; i++) ProblemaMaktub('Problema $i', ubicacion: 'Lugar $i'),
];

void main() {
  testWidgets('sin plegarDesde muestra todo, sin botón', (tester) async {
    await _pump(tester, ListaDeProblemas(titulo: 'Título', problemas: _problemas(5)));

    expect(find.text('Problema 5'), findsOneWidget);
    expect(find.byKey(const Key('lista-de-problemas-detalle')), findsNothing);
  });

  testWidgets('una lista corta se muestra aunque tenga plegarDesde', (tester) async {
    await _pump(
      tester,
      ListaDeProblemas(titulo: 'Título', problemas: _problemas(2), plegarDesde: 3),
    );

    expect(find.text('Problema 2'), findsOneWidget);
    expect(find.byKey(const Key('lista-de-problemas-detalle')), findsNothing);
  });

  testWidgets('una lista larga arranca cerrada y se abre y cierra', (tester) async {
    await _pump(
      tester,
      ListaDeProblemas(titulo: 'Título', problemas: _problemas(4), plegarDesde: 3),
    );
    expect(find.text('Título'), findsOneWidget);
    expect(find.text('Problema 1'), findsNothing);
    expect(find.text('Ver detalle (4)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('lista-de-problemas-detalle')));
    await tester.pump();
    expect(find.text('Problema 4'), findsOneWidget);
    expect(find.text('Lugar 4'), findsOneWidget);

    await tester.tap(find.text('Ocultar detalle'));
    await tester.pump();
    expect(find.text('Problema 1'), findsNothing);
  });
}
