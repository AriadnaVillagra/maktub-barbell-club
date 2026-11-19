import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asks [providers] again when the screen is entered (if they were already loaded) and whenever the app comes back
/// to the front: what another session changes (another coach, an admin) has no push channel, so this is when it
/// shows up. Lists keep what they show while they reload.
class RefreshOnReturn extends ConsumerStatefulWidget {
  const RefreshOnReturn({super.key, required this.providers, required this.child});

  final List<FutureProvider<Object?>> providers;
  final Widget child;

  @override
  ConsumerState<RefreshOnReturn> createState() => _RefreshOnReturnState();
}

class _RefreshOnReturnState extends ConsumerState<RefreshOnReturn> {
  late final _lifecycle = AppLifecycleListener(onResume: _refresh);

  @override
  void initState() {
    super.initState();
    _lifecycle;
    if (widget.providers.any((p) => ref.read(p).hasValue)) Future.microtask(_refresh);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    for (final p in widget.providers) {
      ref.invalidate(p);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
