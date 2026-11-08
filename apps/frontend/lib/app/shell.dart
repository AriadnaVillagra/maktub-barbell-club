import 'dart:ui' show PointerDeviceKind;

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
  static const _modos = [ModoApp.entrenamiento, ModoApp.planificacion, ModoApp.planificacion, ModoApp.planificacion];

  static const _destinos = [
    (icono: Icons.fitness_center_outlined, seleccionado: Icons.fitness_center, etiqueta: 'Entrenamiento'),
    (icono: Icons.edit_calendar_outlined, seleccionado: Icons.edit_calendar, etiqueta: 'Planificación'),
    (icono: Icons.tune_outlined, seleccionado: Icons.tune, etiqueta: 'Preferencias'),
    (icono: Icons.person_outline, seleccionado: Icons.person, etiqueta: 'Perfil'),
  ];

  /// Logical pixels per second that tell a swipe from a slow drag.
  static const _swipeMinVelocity = 300.0;

  void _ir(int indice) => navegacion.goBranch(indice, initialLocation: indice == navegacion.currentIndex);

  /// Indexes (into the branches) of the destinations the user can reach. Planning, Preferences and
  /// Perfil only show up with permission (Perfil: an athlete id in the club); while that isn't known
  /// yet they stay hidden. The branch order never changes, so hiding one shifts nothing.
  static List<int> _visibles(bool canPlan, bool canConfigure, bool hasProfile) =>
      [0, if (canPlan) 1, if (canConfigure) 2, if (hasProfile) 3];

  @override
  Widget build(BuildContext context, WidgetRef ref) => TemaDeModo(
        modo: _modos[navegacion.currentIndex],
        preferencia: ref.watch(preferenciaTemaProvider),
        child: Builder(
          builder: (context) => _construir(
            context,
            _visibles(
              ref.watch(canPlanProvider) ?? false,
              ref.watch(canConfigureProvider) ?? false,
              ref.watch(hasAthleteProfileProvider) ?? false,
            ),
          ),
        ),
      );

  /// A horizontal swipe moves to the next or previous tab. Only from a tab's landing page: inside a
  /// screen (a plan, a form) the same gesture must not throw the user out of it.
  void _swipe(BuildContext context, DragEndDetails details, List<int> visibles) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < _swipeMinVelocity) return;
    if (GoRouter.of(context).state.uri.pathSegments.length != 1) return;
    final next = visibles.indexOf(navegacion.currentIndex) + (velocity < 0 ? 1 : -1);
    if (next >= 0 && next < visibles.length) _ir(visibles[next]);
  }

  Widget _construir(BuildContext context, List<int> visibles) {
    final contenido = Column(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.mouse},
            onHorizontalDragEnd: (d) => _swipe(context, d, visibles),
            child: navegacion,
          ),
        ),
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
