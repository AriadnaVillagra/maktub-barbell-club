import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_ui/maktub_ui.dart';

void main() {
  testWidgets('reserves its size and names itself for screen readers', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: ClubLogo(size: 100))));

    expect(tester.getSize(find.byType(ClubLogo)), const Size(100, 100));
    expect(find.bySemanticsLabel('Logo de Maktub Barbell Club'), findsOneWidget);
  });

  test('the shipped image exists and stays light', () {
    final image = File('assets/logo-club.png');

    expect(image.existsSync(), isTrue);
    expect(image.lengthSync(), lessThan(200 * 1024));
  });
}
