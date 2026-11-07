import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_ui/maktub_ui.dart';

import 'router.dart';

/// Portadas de cada modo. Por ahora listan lo que va a vivir ahí; cada feature
/// reemplaza su entrada por la navegación real a sus pantallas.
class PaginaEntrenamiento extends StatelessWidget {
  const PaginaEntrenamiento({super.key});

  @override
  Widget build(BuildContext context) => const _PortadaModo(
        titulo: 'Entrenamiento',
        descripcion: 'Ejecutar el día con los atletas presentes, en el gimnasio.',
        secciones: [
          (Icons.play_circle_outline, 'Sesión de hoy', 'Objetivos por atleta, pasos y registro en vivo'),
          (Icons.timer_outlined, 'Temporizadores', 'Descansos, EMOM, tabata, AMRAP, for time'),
          (Icons.show_chart, 'Historial', 'Progresión, % real del RM, marcas y WoDs'),
        ],
      );
}

class PaginaPlanificacion extends StatelessWidget {
  const PaginaPlanificacion({super.key});

  @override
  Widget build(BuildContext context) => const _PortadaModo(
        titulo: 'Planificación',
        descripcion: 'Diseñar planes y mantener el catálogo y las referencias de cada atleta.',
        secciones: [
          (Icons.list_alt, 'Catálogo', 'Ejercicios, categorías, equipo y temporizadores'),
          (Icons.people_outline, 'Atletas y referencias', 'RMs, marcas, ritmos, FC y factores de trabajo'),
          (Icons.view_week_outlined, 'Planes', 'Modelos de semana, días, bloques y prescripciones'),
          (Icons.event_available_outlined, 'Asignaciones', 'Plan × grupo × inicio y estado de los días'),
        ],
      );
}

class _PortadaModo extends StatelessWidget {
  const _PortadaModo({required this.titulo, required this.descripcion, required this.secciones});

  final String titulo;
  final String descripcion;
  final List<(IconData, String, String)> secciones;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(titulo)),
        body: ListView(
          padding: const EdgeInsets.all(Espacio.l),
          children: [
            Text(descripcion, style: context.textos.bodyLarge),
            const SizedBox(height: Espacio.l),
            if (titulo == 'Planificación') ...[
              for (final (icono, nombre, ruta) in [
                (Icons.label_outline, 'Categorías', Rutas.categorias),
                (Icons.timer_outlined, 'Temporizadores del club', Rutas.temporizadores),
                (Icons.fitness_center, 'Equipo', Rutas.equipo),
              ])
                Card(
                  child: ListTile(
                    key: Key('catalogo-$ruta'),
                    leading: Icon(icono),
                    title: Text(nombre),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go(ruta),
                  ),
                ),
            ],
            for (final (icono, nombre, detalle) in secciones)
              Card(
                child: ListTile(
                  leading: Icon(icono),
                  title: Text(nombre),
                  subtitle: Text(detalle),
                  trailing: const Chip(label: Text('Próximamente')),
                  enabled: false,
                ),
              ),
          ],
        ),
      );
}
