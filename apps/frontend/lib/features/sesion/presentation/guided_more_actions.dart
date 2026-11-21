import 'package:flutter/material.dart';
import 'package:maktub_ui/maktub_ui.dart';

/// One entry of the guided mode's "Más acciones" sheet.
class GuidedAction {
  const GuidedAction({
    required this.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final Key key;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
}

/// The "Más acciones" button: secondary and destructive actions live in a sheet, away from the main button.
class GuidedMoreActionsButton extends StatelessWidget {
  const GuidedMoreActionsButton({super.key, required this.actions});

  final List<GuidedAction> actions;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        key: const Key('guided-more-actions'),
        icon: const Icon(Icons.more_horiz),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          useSafeArea: true,
          builder: (sheet) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final a in actions)
                ListTile(
                  key: a.key,
                  minTileHeight: context.densidad.tactilMinimo,
                  iconColor: a.destructive ? context.esquema.error : null,
                  textColor: a.destructive ? context.esquema.error : null,
                  leading: Icon(a.icon),
                  title: Text(a.label),
                  onTap: () {
                    Navigator.pop(sheet);
                    a.onTap();
                  },
                ),
            ],
          ),
        ),
        label: const Text('Más acciones'),
      ),
    );
  }
}
