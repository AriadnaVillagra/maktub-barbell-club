import 'package:flutter/material.dart';

import '../tema/contexto.dart';
import '../tokens/colores.dart';
import '../tokens/primitivos.dart';

/// Etiqueta pequeña de un solo texto, con un par de colores semántico
/// (por ejemplo `context.colores.insigniaBase` o `insigniaPropio`). Con [icono], el ícono va antes
/// del texto, para que un estado no se distinga solo por el color.
class InsigniaMaktub extends StatelessWidget {
  const InsigniaMaktub(this.texto, this.colores, {super.key, this.icono});

  final String texto;
  final ParColor colores;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    final estilo = context.textos.labelSmall!.copyWith(color: colores.sobre);
    final etiqueta = Text(texto, style: estilo);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colores.fondo,
        borderRadius: const BorderRadius.all(Radius.circular(Radios.chico)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Espacio.s, vertical: Espacio.xs),
        child: icono == null
            ? etiqueta
            : Row(
                mainAxisSize: MainAxisSize.min,
                spacing: Espacio.xs,
                children: [
                  Icon(icono, size: estilo.fontSize, color: colores.sobre),
                  Flexible(child: etiqueta),
                ],
              ),
      ),
    );
  }
}
