import 'package:flutter/material.dart';
import 'package:maktub_core/maktub_core.dart';
import 'package:maktub_ui/maktub_ui.dart';

/// One block of the day as a card: its name, its note if it has one, and [children] with the exercises.
class SessionBlockCard extends StatelessWidget {
  const SessionBlockCard({
    super.key,
    required this.block,
    required this.children,
    this.action,
  });

  final PlanBlock block;
  final List<Widget> children;

  /// Goes under the note, for what the block itself does, such as starting its timer.
  final Widget? action;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(Espacio.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(block.name, style: context.textos.titleMedium),
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
    ),
  );
}
