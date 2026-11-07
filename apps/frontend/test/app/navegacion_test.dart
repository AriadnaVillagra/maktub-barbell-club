import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_frontend/app/app.dart';

Future<void> _montar(WidgetTester tester, Size tamano) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const ProviderScope(child: MaktubApp()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('arranca en Entrenamiento y navega a Planificación (celular)', (tester) async {
    await _montar(tester, const Size(400, 800));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Sesión de hoy'), findsOneWidget);

    await tester.tap(find.text('Planificación'));
    await tester.pumpAndSettle();

    expect(find.text('Catálogo'), findsOneWidget);
    expect(find.text('Sesión de hoy'), findsNothing);
  });

  testWidgets('entrenamiento abre en oscuro y planificación sigue al sistema (claro)', (tester) async {
    await _montar(tester, const Size(400, 800));
    Brightness brillo() => Theme.of(tester.element(find.byType(NavigationBar))).brightness;

    expect(brillo(), Brightness.dark);

    await tester.tap(find.text('Planificación'));
    await tester.pumpAndSettle();

    expect(brillo(), Brightness.light);
  });

  testWidgets('en pantallas anchas usa un riel lateral', (tester) async {
    await _montar(tester, const Size(1200, 800));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
