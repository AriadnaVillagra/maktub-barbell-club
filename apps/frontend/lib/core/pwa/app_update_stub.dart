import 'app_update.dart';

/// Outside the web there is no service worker: never an update.
AppUpdate createAppUpdate() => _NoUpdate();

class _NoUpdate implements AppUpdate {
  @override
  bool get ready => false;

  @override
  void listen(void Function() onReady) {}

  @override
  void apply() {}
}
