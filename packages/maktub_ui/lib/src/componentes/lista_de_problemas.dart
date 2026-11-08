import 'package:flutter/material.dart';

import '../tema/contexto.dart';
import '../tokens/primitivos.dart';

/// One problem of a [ListaDeProblemas]: [mensaje] says what is wrong and [ubicacion], when there is one,
/// where it is ("Modelo A › Día 2 › Bloque 1").
class ProblemaMaktub {
  const ProblemaMaktub(this.mensaje, {this.ubicacion});

  final String mensaje;
  final String? ubicacion;
}

/// Error notice with a title and the complete list of what went wrong, for forms that refuse to
/// save (every problem at once, not just the first). Announced to screen readers when it appears.
class ListaDeProblemas extends StatelessWidget {
  const ListaDeProblemas({super.key, required this.titulo, this.problemas = const []});

  final String titulo;
  final List<ProblemaMaktub> problemas;

  @override
  Widget build(BuildContext context) {
    final color = context.esquema.onErrorContainer;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(Espacio.m),
        decoration: BoxDecoration(
          color: context.esquema.errorContainer,
          borderRadius: const BorderRadius.all(Radius.circular(Radios.medio)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: color),
            const SizedBox(width: Espacio.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: context.textos.titleSmall?.copyWith(color: color)),
                  for (final p in problemas)
                    Padding(
                      padding: const EdgeInsets.only(top: Espacio.s),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (p.ubicacion != null)
                            Text(p.ubicacion!, style: context.textos.labelMedium?.copyWith(color: color)),
                          Text(p.mensaje, style: context.textos.bodyMedium?.copyWith(color: color)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
