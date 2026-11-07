import 'package:flutter/material.dart';

import '../tema/contexto.dart';
import '../tokens/colores.dart';
import '../tokens/primitivos.dart';

/// Etiqueta pequeña de un solo texto, con un par de colores semántico
/// (por ejemplo `context.colores.insigniaBase` o `insigniaPropio`).
class InsigniaMaktub extends StatelessWidget {
  const InsigniaMaktub(this.texto, this.colores, {super.key});

  final String texto;
  final ParColor colores;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: colores.fondo,
          borderRadius: const BorderRadius.all(Radius.circular(Radios.chico)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Espacio.s, vertical: Espacio.xs),
          child: Text(texto, style: context.textos.labelSmall!.copyWith(color: colores.sobre)),
        ),
      );
}
