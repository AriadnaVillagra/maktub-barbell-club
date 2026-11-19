import 'package:flutter/material.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

/// Hoja inferior para elegir uno de los temporizadores a mano. [onConfigure] lleva a la pantalla donde se eligen
/// cuáles son; sin ninguno, la hoja solo ofrece eso.
Future<Temporizador?> elegirTemporizador(
  BuildContext context,
  Iterable<Temporizador> temporizadores, {
  VoidCallback? onConfigure,
}) {
  final lista = temporizadores.toList();
  return showModalBottomSheet<Temporizador>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final configurar = onConfigure == null
          ? null
          : TextButton.icon(
              key: const Key('timer-picker-configure'),
              icon: const Icon(Icons.checklist),
              label: Text(lista.isEmpty ? 'Elegir temporizadores' : 'Cambiar cuáles aparecen'),
              onPressed: () {
                Navigator.pop(context);
                onConfigure();
              },
            );
      if (lista.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(Espacio.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Todavía no elegiste temporizadores a mano. Marcalos en Preferencias → Temporizadores.',
                key: Key('timer-picker-empty'),
              ),
              if (configurar != null) ...[const SizedBox(height: Espacio.m), configurar],
            ],
          ),
        );
      }
      return ListView(
        shrinkWrap: true,
        children: [
          for (final t in lista)
            ListTile(
              key: Key('timer-pick-${t.id}'),
              leading: const Icon(Icons.timer_outlined),
              title: Text(t.nombre),
              subtitle: Text(describirTemporizador(t)),
              onTap: () => Navigator.pop(context, t),
            ),
          if (configurar != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Espacio.m, vertical: Espacio.s),
              child: Align(alignment: Alignment.centerLeft, child: configurar),
            ),
        ],
      );
    },
  );
}
