import 'package:flutter/material.dart';

import '../tema/contexto.dart';
import '../tokens/primitivos.dart';
import 'insignia.dart';

/// How far an athlete got through a day, as an icon and a text (never color alone): "Hecho" when [done], "En curso"
/// with [doneSets] of [totalSets] when some sets are done, else "Pendiente". Without [totalSets] the in-progress
/// badge carries no count.
class DayStatusBadge extends StatelessWidget {
  const DayStatusBadge({super.key, required this.done, this.doneSets = 0, this.totalSets});

  final bool done;
  final int doneSets;
  final int? totalSets;

  static const doneLabel = 'Hecho';
  static const inProgressLabel = 'En curso';
  static const pendingLabel = 'Pendiente';

  /// The badge's text, for places that show the state as plain text, such as a pill's detail.
  static String labelOf({required bool done, int doneSets = 0, int? totalSets}) => done
      ? doneLabel
      : doneSets > 0
          ? (totalSets == null ? inProgressLabel : '$inProgressLabel $doneSets/$totalSets')
          : pendingLabel;

  @override
  Widget build(BuildContext context) {
    final label = labelOf(done: done, doneSets: doneSets, totalSets: totalSets);
    return done
        ? InsigniaMaktub(label, context.colores.exitoContenedor, icono: Icons.check_circle)
        : doneSets > 0
            ? InsigniaMaktub(label, context.colores.alertaContenedor, icono: Icons.timelapse)
            : InsigniaMaktub(label, context.colores.insigniaBase, icono: Icons.radio_button_unchecked);
  }
}

/// One day of a plan's calendar: its title, how far it is done ([DayStatusBadge]), and what the screen puts under
/// it. [highlighted] marks the day that comes next with a strong accent border and the
/// [highlightLabel] badge; [selected] marks the day whose detail is open. With [onTap] the whole card is a button at
/// least as tall as the active density's touch side.
class DayCard extends StatelessWidget {
  const DayCard({
    super.key,
    required this.title,
    required this.done,
    this.doneSets = 0,
    this.totalSets,
    this.subtitle,
    this.highlighted = false,
    this.highlightLabel = nextLabel,
    this.selected = false,
    this.onTap,
    this.children = const [],
    this.action,
  });

  final String title;

  /// A smaller line under [title], such as the day's name.
  final String? subtitle;
  final bool done;

  /// Sets done out of the planned ones, for a day in progress ([DayStatusBadge]).
  final int doneSets;
  final int? totalSets;
  final bool highlighted;
  final String highlightLabel;
  final bool selected;
  final VoidCallback? onTap;

  /// The day's content, under the badges.
  final List<Widget> children;

  /// Goes last, full width, such as the button that opens the day.
  final Widget? action;

  static const nextLabel = 'Toca hoy';

  /// Widths a calendar lays days out with: a grid cell, the week's label beside a row of cells, a card with its
  /// blocks, and a day in full (also the side panel that shows one).
  static const cellWidth = 168.0;
  static const weekLabelWidth = 112.0;
  static const cardWidth = 256.0;
  static const detailWidth = 360.0;

  @override
  Widget build(BuildContext context) {
    final esquema = context.esquema;
    final borde = highlighted
        ? BorderSide(color: context.colores.acento, width: Borde.marcado)
        : selected
            ? BorderSide(color: esquema.primary, width: Borde.marcado)
            : BorderSide(color: esquema.outlineVariant, width: Borde.fino);
    return Semantics(
      button: onTap != null,
      selected: selected,
      child: Material(
        color: selected ? esquema.surfaceContainerHigh : esquema.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(Radios.medio)),
          side: borde,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: context.densidad.tactilMinimo),
            child: Padding(
              padding: const EdgeInsets.all(Espacio.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.textos.titleSmall),
                  if (subtitle case final subtitle? when subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: context.textos.bodySmall!.copyWith(color: esquema.onSurfaceVariant),
                    ),
                  const SizedBox(height: Espacio.s),
                  Wrap(
                    spacing: Espacio.xs,
                    runSpacing: Espacio.xs,
                    children: [
                      DayStatusBadge(done: done, doneSets: doneSets, totalSets: totalSets),
                      if (highlighted)
                        InsigniaMaktub(highlightLabel, context.colores.turnoActivo, icono: Icons.arrow_forward),
                    ],
                  ),
                  if (children.isNotEmpty) ...[
                    const SizedBox(height: Espacio.s),
                    ...children,
                  ],
                  if (action case final action?) ...[
                    const SizedBox(height: Espacio.m),
                    SizedBox(width: double.infinity, child: action),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
