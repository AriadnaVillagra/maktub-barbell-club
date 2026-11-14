import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_ui/maktub_ui.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget card, {ModoApp modo = ModoApp.entrenamiento}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: TemaMaktub.para(Brightness.dark, modo.densidad),
          home: Scaffold(body: Center(child: SizedBox(width: 200, child: card))),
        ),
      );

  testWidgets('a done day says so with an icon and text', (tester) async {
    await pump(tester, const DayCard(title: 'Día 1', done: true));
    expect(find.text('Hecho'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.text('Pendiente'), findsNothing);
  });

  testWidgets('a pending day says so with an icon and text', (tester) async {
    await pump(tester, const DayCard(title: 'Día 1', done: false));
    expect(find.text('Pendiente'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
  });

  testWidgets('the highlighted day carries its label', (tester) async {
    await pump(tester, const DayCard(title: 'Día 2', done: false, highlighted: true));
    expect(find.text('Toca hoy'), findsOneWidget);
  });

  for (final modo in [ModoApp.entrenamiento, ModoApp.planificacion]) {
    testWidgets('in $modo it meets the touch size and reports the tap', (tester) async {
      var taps = 0;
      await pump(tester, DayCard(title: 'Día 1', done: false, onTap: () => taps++), modo: modo);
      expect(tester.getSize(find.byType(DayCard)).height, greaterThanOrEqualTo(modo.densidad.tactilMinimo));
      await tester.tap(find.byType(DayCard));
      expect(taps, 1);
    });
  }

  testWidgets('a selected day is announced as selected', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, DayCard(title: 'Día 1', done: false, selected: true, onTap: () {}));
    expect(
      tester.getSemantics(find.byType(DayCard)),
      isSemantics(isSelected: true, isButton: true),
    );
    handle.dispose();
  });
}
