import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../features/access/presentation/providers.dart';
import 'router.dart';

/// Portadas de cada modo. Por ahora listan lo que va a vivir ahí; cada feature
/// reemplaza su entrada por la navegación real a sus pantallas.
class PaginaEntrenamiento extends ConsumerWidget {
  const PaginaEntrenamiento({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _PortadaModo(
        titulo: 'Entrenamiento',
        descripcion: 'Ejecutar el día con los atletas presentes, en el gimnasio.',
        secciones: [
          (Icons.play_circle_outline, 'Sesión del día', 'Presentes y kilos de cada serie, y el calendario del plan', Rutas.sesion),
          // The own history needs an athlete profile in the active club.
          if (ref.watch(hasAthleteProfileProvider) ?? false)
            (Icons.history, 'Mi historial', 'Tus sesiones pasadas, con kilos y repeticiones', Rutas.historial),
        ],
      );
}

/// Only reached by coach and up (the router sends the rest to training), so every entry shows.
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

/// What configures the club rather than a plan. Each entry shows by the permission it needs (by hierarchy: coach
/// the catalog, club admin also equipment and members, platform admin also club requests and the club picker).
class PaginaPreferencias extends ConsumerWidget {
  const PaginaPreferencias({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('Preferencias')),
        body: ListView(
          padding: const EdgeInsets.all(Espacio.l),
          children: [
            for (final (icono, nombre, ruta) in [
              if (ref.watch(canEditClubCatalogProvider)) ...[
                (Icons.list_alt, 'Ejercicios', Rutas.catalogo),
                (Icons.fitness_center, 'Categorías', Rutas.categorias),
                (Icons.timer_outlined, 'Temporizadores', Rutas.temporizadores),
              ],
              if (ref.watch(canPlanProvider) ?? false) (Icons.local_fire_department_outlined, 'WoDs', Rutas.wods),
              if (ref.watch(canEditEquipmentProvider)) (Icons.inventory_2_outlined, 'Equipo', Rutas.equipo),
              if (ref.watch(canManageMembersProvider)) (Icons.group_outlined, 'Miembros', Rutas.miembros),
              if (ref.watch(isPlatformAdminProvider)) (Icons.domain_add_outlined, 'Pedidos de clubes', Rutas.pedidosClub),
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
