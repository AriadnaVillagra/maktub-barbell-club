import 'package:flutter/material.dart';

import '../tokens/densidad.dart';
import 'tema_maktub.dart';

/// Los dos modos de la app (docs/diseno.md, "Visión"). Cada uno tiene su densidad.
enum ModoApp {
  planificacion(Densidad.planificacion),
  entrenamiento(Densidad.entrenamiento);

  const ModoApp(this.densidad);
  final Densidad densidad;
}

/// Lo que eligió el usuario. `sistema` es el default.
enum PreferenciaTema { sistema, claro, oscuro }

/// Entrenamiento abre en oscuro salvo que el usuario fije claro; el resto sigue al sistema
/// salvo que el usuario fije uno (F17, principio 5).
Brightness brilloPara(ModoApp modo, PreferenciaTema preferencia, Brightness sistema) => switch (preferencia) {
      PreferenciaTema.claro => Brightness.light,
      PreferenciaTema.oscuro => Brightness.dark,
      PreferenciaTema.sistema => modo == ModoApp.entrenamiento ? Brightness.dark : sistema,
    };

/// Aplica el tema y la densidad de [modo] a su subárbol.
class TemaDeModo extends StatelessWidget {
  const TemaDeModo({
    super.key,
    required this.modo,
    required this.child,
    this.preferencia = PreferenciaTema.sistema,
  });

  final ModoApp modo;
  final PreferenciaTema preferencia;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brillo = brilloPara(modo, preferencia, MediaQuery.platformBrightnessOf(context));
    return AnimatedTheme(
      data: TemaMaktub.para(brillo, modo.densidad),
      duration: Movimiento.en(context, Movimiento.medio),
      child: child,
    );
  }
}
