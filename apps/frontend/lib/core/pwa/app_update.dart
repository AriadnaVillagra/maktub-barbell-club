import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_update_stub.dart' if (dart.library.js_interop) 'app_update_web.dart';

/// A new version of the PWA that the service worker already downloaded and keeps waiting (see `web/index.html`).
abstract interface class AppUpdate {
  /// Whether one was already waiting when this was asked.
  bool get ready;

  /// Calls [onReady] when one finishes downloading while the app is open.
  void listen(void Function() onReady);

  /// Activates it; the page reloads into it.
  void apply();
}

/// The browser's service worker. Tests override it with a fake.
final appUpdateProvider = Provider<AppUpdate>((ref) => createAppUpdate());

/// Whether a new version is waiting to be applied.
final appUpdateReadyProvider = NotifierProvider<AppUpdateReady, bool>(AppUpdateReady.new);

class AppUpdateReady extends Notifier<bool> {
  @override
  bool build() {
    final update = ref.watch(appUpdateProvider);
    update.listen(() {
      if (ref.mounted) state = true;
    });
    return update.ready;
  }
}
