import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maktub_ui/maktub_ui.dart';

import 'providers.dart';

/// Scrolls [child] into view when it is what the editor just added ([planRevealProvider] equals
/// [target]), so adding a day, block or exercise takes the coach to it.
class RevealOnAdd extends ConsumerStatefulWidget {
  const RevealOnAdd({super.key, required this.target, required this.child});

  final String target;
  final Widget child;

  @override
  ConsumerState<RevealOnAdd> createState() => _RevealOnAddState();
}

class _RevealOnAddState extends ConsumerState<RevealOnAdd> {
  bool _scheduled = false;

  @override
  Widget build(BuildContext context) {
    if (ref.watch(planRevealProvider) == widget.target && !_scheduled) {
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduled = false;
        if (!mounted) return;
        ref.read(planRevealProvider.notifier).done(widget.target);
        Scrollable.ensureVisible(
          context,
          duration: Movimiento.medio,
          curve: Curves.easeOut,
          alignment: 0.1,
        );
      });
    }
    return widget.child;
  }
}
