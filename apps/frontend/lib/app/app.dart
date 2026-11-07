import 'package:flutter/material.dart';

import '../features/seguimiento/presentation/pages/seguimiento_page.dart';

class MaktubApp extends StatelessWidget {
  const MaktubApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData tema(Brightness brillo) => ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFB71C1C), brightness: brillo),
          useMaterial3: true,
        );

    return MaterialApp(
      title: 'Maktub Barbell Club',
      debugShowCheckedModeBanner: false,
      theme: tema(Brightness.light),
      darkTheme: tema(Brightness.dark),
      home: const SeguimientoPage(),
    );
  }
}
