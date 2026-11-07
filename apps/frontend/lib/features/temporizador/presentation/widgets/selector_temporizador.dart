import 'package:flutter/material.dart';
import 'package:maktub_core/maktub_core.dart';

/// Hoja inferior para elegir un temporizador del catálogo.
Future<Temporizador?> elegirTemporizador(BuildContext context, Iterable<Temporizador> temporizadores) {
  final lista = temporizadores.toList();
  return showModalBottomSheet<Temporizador>(
    context: context,
    showDragHandle: true,
    builder: (context) => lista.isEmpty
        ? const Padding(padding: EdgeInsets.all(24), child: Text('No hay temporizadores cargados.'))
        : ListView(
            shrinkWrap: true,
            children: [
              for (final t in lista)
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: Text(t.nombre),
                  subtitle: Text(describirTemporizador(t)),
                  onTap: () => Navigator.pop(context, t),
                ),
            ],
          ),
  );
}
