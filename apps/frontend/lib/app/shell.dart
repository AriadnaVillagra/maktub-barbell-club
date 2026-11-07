import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_ui/maktub_ui.dart';

import '../features/access/presentation/providers.dart';
import '../features/temporizador/presentation/widgets/barra_crono.dart';
import 'preferencias.dart';

/// Marco común: navegación entre modos (barra inferior en celular, riel lateral desde tablet),
/// el tema de cada modo (entrenamiento oscuro y grande) y el temporizador en marcha.
class ShellPrincipal extends ConsumerWidget {
  const ShellPrincipal({super.key, required this.navegacion});

  final StatefulNavigationShell navegacion;

  /// En el mismo orden que las ramas del router.
  static const _modos = [ModoApp.entrenamiento, ModoApp.planificacion];

  static const _destinos = [
    (icono: Icons.fitness_center_outlined, seleccionado: Icons.fitness_center, etiqueta: 'Entrenamiento'),
    (icono: Icons.edit_calendar_outlined, seleccionado: Icons.edit_calendar, etiqueta: 'Planificación'),
  ];

  void _ir(int indice) => navegacion.goBranch(indice, initialLocation: indice == navegacion.currentIndex);

  /// Indexes (into the branches) of the destinations the user can reach. Planning only shows up
  /// with permission; while that isn't known yet it stays hidden.
  static List<int> _visibles(bool canPlan) => [0, if (canPlan) 1];

  @override
  Widget build(BuildContext context, WidgetRef ref) => TemaDeModo(
        modo: _modos[navegacion.currentIndex],
        preferencia: ref.watch(preferenciaTemaProvider),
        child: Builder(builder: (context) => _construir(context, _visibles(ref.watch(canPlanProvider) ?? false))),
      );

  Widget _construir(BuildContext context, List<int> visibles) {
    final contenido = Column(
      children: [
        Expanded(child: navegacion),
        const BarraCrono(),
      ],
    );

    // A single destination has nowhere to navigate to, so there is no bar.
    if (visibles.length < 2) return Scaffold(body: contenido);

    if (context.tamanoPantalla != TamanoPantalla.compacto) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: visibles.indexOf(navegacion.currentIndex).clamp(0, visibles.length - 1),
              onDestinationSelected: (i) => _ir(visibles[i]),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in [for (final i in visibles) _destinos[i]])
                  NavigationRailDestination(
                    icon: Icon(d.icono),
                    selectedIcon: Icon(d.seleccionado),
                    label: Text(d.etiqueta),
                  ),
              ],
            ),
            const VerticalDivider(width: Borde.fino),
            Expanded(child: contenido),
          ],
        ),
      );
    }

    return Scaffold(
      body: contenido,
      bottomNavigationBar: NavigationBar(
        selectedIndex: visibles.indexOf(navegacion.currentIndex).clamp(0, visibles.length - 1),
        onDestinationSelected: (i) => _ir(visibles[i]),
        destinations: [
          for (final d in [for (final i in visibles) _destinos[i]])
            NavigationDestination(icon: Icon(d.icono), selectedIcon: Icon(d.seleccionado), label: d.etiqueta),
        ],
      ),
    );
  }
}
