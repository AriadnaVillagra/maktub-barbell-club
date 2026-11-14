import 'package:flutter/material.dart';

import '../tema/contexto.dart';
import '../tokens/primitivos.dart';
import 'insignia.dart';

/// One day of a plan's calendar: its title, whether it is done or pending (icon and text, never color alone), and
/// what the screen puts under it. [highlighted] marks the day that comes next with a strong accent border and the
/// [highlightLabel] badge; [selected] marks the day whose detail is open. With [onTap] the whole card is a button at
/// least as tall as the active density's touch side.
class DayCard extends StatelessWidget {
  const DayCard({
    super.key,
    required this.title,
    required this.done,
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
  final bool highlighted;
  final String highlightLabel;
  final bool selected;
  final VoidCallback? onTap;

  /// The day's content, under the badges.
  final List<Widget> children;

  /// Goes last, full width, such as the button that opens the day.
  final Widget? action;

  static const doneLabel = 'Hecho';
  static const pendingLabel = 'Pendiente';
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
                      done
                          ? InsigniaMaktub(doneLabel, context.colores.exitoContenedor, icono: Icons.check_circle)
                          : InsigniaMaktub(
                              pendingLabel,
                              context.colores.insigniaBase,
                              icono: Icons.radio_button_unchecked,
                            ),
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
