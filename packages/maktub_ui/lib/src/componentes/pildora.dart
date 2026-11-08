import 'package:flutter/material.dart';

import '../tema/contexto.dart';
import '../tokens/primitivos.dart';

/// Opción de una fila de selección única (semana, día): un texto, una línea chica opcional debajo y un
/// estado seleccionado. Mide al menos el lado táctil de la densidad activa.
class PildoraMaktub extends StatelessWidget {
  const PildoraMaktub({
    super.key,
    required this.texto,
    required this.seleccionada,
    required this.onTap,
    this.detalle,
  });

  final String texto;

  /// Línea chica bajo [texto], como el nombre del modelo de una semana.
  final String? detalle;
  final bool seleccionada;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final par = context.colores.botonPrimario;
    final colorTexto = seleccionada ? par.sobre : context.esquema.onSurface;
    return Semantics(
      button: true,
      selected: seleccionada,
      child: Material(
        color: seleccionada ? par.fondo : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(
            Radius.circular(Radios.pastilla),
          ),
          side: BorderSide(
            color: seleccionada ? par.fondo : context.esquema.outline,
            width: Borde.fino,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: context.densidad.tactilMinimo,
              minWidth: context.densidad.tactilMinimo,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Espacio.l,
                vertical: Espacio.xs,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    texto,
                    style: context.textos.labelLarge!.copyWith(
                      color: colorTexto,
                    ),
                  ),
                  if (detalle != null)
                    Text(
                      detalle!,
                      style: context.textos.labelSmall!.copyWith(
                        color: colorTexto,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
