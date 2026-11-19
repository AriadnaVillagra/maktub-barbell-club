/// Steps back in the browser's history, like the browser's back button. Outside the browser it does nothing.
library;

export 'browser_history_stub.dart' if (dart.library.js_interop) 'browser_history_web.dart';
