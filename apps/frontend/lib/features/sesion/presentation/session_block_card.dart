import 'package:flutter/material.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

/// One block of the day as a card: its name, its note if it has one, and [children] with the exercises.
///
/// With [onToggle] the header is tappable and folds the card: collapsed, it shows only the name and the one-line
/// [summary]. Without it the card is always open.
class SessionBlockCard extends StatelessWidget {
  const SessionBlockCard({
    super.key,
    required this.block,
    required this.children,
    this.action,
    this.collapsed = false,
    this.summary,
    this.onToggle,
    this.toggleKey,
  });

  final PlanBlock block;
  final List<Widget> children;

  /// Goes under the note, for what the block itself does, such as starting its timer.
  final Widget? action;

  /// Whether only the header shows. Ignored without [onToggle].
  final bool collapsed;

  /// Shown under the name while collapsed, such as the exercise names.
  final String? summary;

  /// Folds or unfolds the card; null leaves it not collapsible.
  final VoidCallback? onToggle;

  /// Key of the tappable header, for tests.
  final Key? toggleKey;

  @override
  Widget build(BuildContext context) {
    final folded = onToggle != null && collapsed;
    final title = Text(block.name, style: context.textos.titleMedium);
    return SizedBox(
      width: double.infinity,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (onToggle case final onToggle?)
              InkWell(
                key: toggleKey,
                onTap: onToggle,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: context.densidad.tactilMinimo,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Espacio.m,
                      Espacio.xs,
                      Espacio.s,
                      Espacio.xs,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              title,
                              if (folded && (summary ?? '').isNotEmpty)
                                Text(
                                  summary!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.textos.bodySmall,
                                ),
                            ],
                          ),
                        ),
                        Icon(
                          folded ? Icons.expand_more : Icons.expand_less,
                          semanticLabel: folded ? 'Expandir' : 'Colapsar',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (!folded)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  Espacio.m,
                  onToggle == null ? Espacio.m : 0,
                  Espacio.m,
                  Espacio.m,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (onToggle == null) title,
                    if (block.note case final note? when note.isNotEmpty)
                      Text(note, style: context.textos.bodySmall),
                    if (action case final action?) ...[
                      const SizedBox(height: Espacio.s),
                      action,
                    ],
                    const SizedBox(height: Espacio.s),
                    ...children,
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
