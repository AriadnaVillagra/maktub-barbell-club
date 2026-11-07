import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maktub_ui/maktub_ui.dart';

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

  @override
  Widget build(BuildContext context, WidgetRef ref) => TemaDeModo(
        modo: _modos[navegacion.currentIndex],
        preferencia: ref.watch(preferenciaTemaProvider),
        child: Builder(builder: _construir),
      );

  Widget _construir(BuildContext context) {
    final contenido = Column(
      children: [
        Expanded(child: navegacion),
        const BarraCrono(),
      ],
    );

    if (context.tamanoPantalla != TamanoPantalla.compacto) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: navegacion.currentIndex,
              onDestinationSelected: _ir,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinos)
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
        selectedIndex: navegacion.currentIndex,
        onDestinationSelected: _ir,
        destinations: [
          for (final d in _destinos)
            NavigationDestination(icon: Icon(d.icono), selectedIcon: Icon(d.seleccionado), label: d.etiqueta),
        ],
      ),
    );
  }
}
