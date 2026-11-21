import 'package:flutter/material.dart';

import '../tema/contexto.dart';
import '../tokens/primitivos.dart';

/// Manija para reordenar una lista con `ReorderableListView` (con `buildDefaultDragHandles: false`).
///
/// Mide al menos el mínimo táctil de la densidad y se dibuja como un botón suave, para que se vea que
/// se agarra y no se confunda con los botones de al lado. Poné margen entre ella y los vecinos.
class ManijaArrastre extends StatelessWidget {
  const ManijaArrastre({super.key, required this.index, this.tooltip = 'Mover'});

  /// Posición del ítem en la lista reordenable.
  final int index;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final lado = context.densidad.tactilMinimo;
    return ReorderableDragStartListener(
      index: index,
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: lado,
          height: lado,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.esquema.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(Radios.medio),
          ),
          child: Icon(Icons.drag_indicator, color: context.esquema.onSurfaceVariant),
        ),
      ),
    );
  }
}
