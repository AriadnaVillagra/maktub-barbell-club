import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_frontend/app/app.dart';
import 'package:maktub_frontend/features/seguimiento/presentation/providers.dart';

import '../../../datos_de_prueba.dart';
import '../../../repositorio_falso.dart';

void main() {
  testWidgets('muestra el día con los kilos calculados y guarda', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repo = RepositorioFalso(snapshotDePrueba());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        seguimientoRepositoryProvider.overrideWithValue(repo),
        hoyProvider.overrideWithValue(() => DateTime.utc(2026, 11, 3)), // semana 1: descarga
      ],
      child: const MaktubApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Día 1 · Sentadilla'), findsOneWidget);
    expect(find.text('Biserie'), findsOneWidget);
    expect(find.textContaining('sin peso fijo'), findsOneWidget); // face pull sin kilaje

    await tester.tap(find.text('Guardar día'));
    await tester.pumpAndSettle();

    expect(repo.guardadas, hasLength(1));
    expect(find.text('Actualizar registro'), findsOneWidget);
  });
}
