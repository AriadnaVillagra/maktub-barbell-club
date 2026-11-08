import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../features/access/presentation/providers.dart';
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
          (Icons.calendar_month_outlined, 'Calendario', 'Semanas y días del plan asignado al grupo', Rutas.calendario),
          (Icons.timer_outlined, 'Temporizadores', 'Descansos, EMOM, tabata, AMRAP, for time', null),
          (Icons.show_chart, 'Historial', 'Progresión, % real del RM, marcas y WoDs', null),
        ],
      );
}

class PaginaPlanificacion extends StatelessWidget {
  const PaginaPlanificacion({super.key});

  @override
  Widget build(BuildContext context) => const _PortadaModo(
        titulo: 'Planificación',
        descripcion: 'Diseñar planes y mantener las referencias de cada atleta.',
        secciones: [
          (Icons.people_outline, 'Atletas y referencias', 'RMs, marcas, ritmos, FC y factores de trabajo', Rutas.atletas),
          (Icons.view_week_outlined, 'Planes', 'Modelos de semana, días, bloques y prescripciones', Rutas.planes),
          (Icons.event_available_outlined, 'Asignaciones', 'Plan × grupo × inicio y estado de los días', Rutas.asignaciones),
        ],
      );
}

/// What configures the club rather than a plan.
class PaginaPreferencias extends ConsumerWidget {
  const PaginaPreferencias({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('Preferencias')),
        body: ListView(
          padding: const EdgeInsets.all(Espacio.l),
          children: [
            for (final (icono, nombre, ruta) in [
              (Icons.list_alt, 'Ejercicios', Rutas.catalogo),
              (Icons.fitness_center, 'Categorías', Rutas.categorias),
              (Icons.timer_outlined, 'Temporizadores', Rutas.temporizadores),
              if (ref.watch(canPlanProvider) ?? false) (Icons.local_fire_department_outlined, 'WoDs', Rutas.wods),
              (Icons.inventory_2_outlined, 'Equipo', Rutas.equipo),
              if (ref.watch(canManageMembersProvider)) (Icons.group_outlined, 'Miembros', Rutas.miembros),
            ])
              Card(
                child: ListTile(
                  key: Key('preferencia-$ruta'),
                  leading: Icon(icono),
                  title: Text(nombre),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(ruta),
                ),
              ),
          ],
        ),
      );
}

class _PortadaModo extends StatelessWidget {
  const _PortadaModo({required this.titulo, required this.descripcion, required this.secciones});

  final String titulo;
  final String descripcion;
  /// Icon, name, detail and the route it opens (null while the feature is not built).
  final List<(IconData, String, String, String?)> secciones;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(titulo)),
        body: ListView(
          padding: const EdgeInsets.all(Espacio.l),
          children: [
            Text(descripcion, style: context.textos.bodyLarge),
            const SizedBox(height: Espacio.l),
            for (final (icono, nombre, detalle, ruta) in secciones)
              Card(
                child: ListTile(
                  key: ruta == null ? null : Key('portada-$ruta'),
                  leading: Icon(icono),
                  title: Text(nombre),
                  subtitle: Text(detalle),
                  trailing: ruta == null ? const Chip(label: Text('Próximamente')) : const Icon(Icons.chevron_right),
                  enabled: ruta != null,
                  onTap: ruta == null ? null : () => context.go(ruta),
                ),
              ),
          ],
        ),
      );
}
