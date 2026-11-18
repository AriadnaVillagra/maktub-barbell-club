import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'app_update.dart';

/// Talks to `window.maktubUpdate`, which `web/index.html` sets up when it registers the service worker.
AppUpdate createAppUpdate() => _WebAppUpdate();

@JS('maktubUpdate')
external _MaktubUpdate? get _maktubUpdate;

extension type _MaktubUpdate(JSObject _) implements JSObject {
  external bool get ready;
  external void apply();
}

class _WebAppUpdate implements AppUpdate {
  @override
  bool get ready => _maktubUpdate?.ready ?? false;

  @override
  void listen(void Function() onReady) =>
      web.window.addEventListener('maktub-update', ((web.Event _) => onReady()).toJS);

  @override
  void apply() => _maktubUpdate?.apply();
}
